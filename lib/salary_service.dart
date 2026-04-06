import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:enough_mail/enough_mail.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class SalaryRecord {
  final String salaryMonth;
  final String netSalary;
  final String remainingLeave;
  final DateTime? emailDate;
  final int? mailUid;

  SalaryRecord({
    required this.salaryMonth,
    required this.netSalary,
    required this.remainingLeave,
    this.emailDate,
    this.mailUid,
  });

  Map<String, String> toMap() => {
    'salary_month': salaryMonth,
    'salary': netSalary,
    'remaining_leave': remainingLeave,
    'email_date': emailDate?.toIso8601String() ?? '',
    'mail_uid': mailUid?.toString() ?? '',
  };

  factory SalaryRecord.fromMap(Map<String, String> map) {
    final month = map['salary_month'] ?? '--';
    var leave = map['remaining_leave'] ?? '--';
    
    // Nếu là tháng 13/14 (thưởng), không có phép năm thì để '--'
    if (RegExp(r'1[34]/').hasMatch(month)) {
      leave = '--';
    }

    return SalaryRecord(
      salaryMonth: month,
      netSalary: map['salary'] ?? '--',
      remainingLeave: leave,
      emailDate: map['email_date'] != null && map['email_date']!.isNotEmpty
          ? DateTime.tryParse(map['email_date']!)
          : null,
      mailUid: map['mail_uid'] != null && map['mail_uid']!.isNotEmpty
          ? int.tryParse(map['mail_uid']!)
          : null,
    );
  }
}

class SalaryService {
  static const String mailEmail = 'tandungluu338@gmail.com';
  static const String mailPassword = 'dunw trqk yszj jmjz'; // App password
  static const String incomingHost = 'imap.gmail.com';
  static const int incomingPort = 993;
  static const String expectedSender = 'lg.la@tpgroup.com.vn';

  Future<List<SalaryRecord>> fetchSalaryFromMail({int? lastProcessedUid}) async {
    print('[SalaryService] === START fetchSalaryFromMail ===');
    print('[SalaryService] lastProcessedUid: $lastProcessedUid');
    
    final imapClient = ImapClient(isLogEnabled: false);
    var connected = false;

    try {
      await imapClient.connectToServer(incomingHost, incomingPort, isSecure: true);
      connected = true;
      await imapClient.login(mailEmail, mailPassword);
      print('[SalaryService] Connected to IMAP');
      await imapClient.selectInbox();

      // BẢN SỬA LỖI: Sửa lỗi "BAD Could not parse command" bằng cách quay lại dùng SINCE 
      // nhưng tăng khoảng thời gian lên 180 ngày để bao phủ được trường hợp 3-5 tháng không vào app.
      final sinceDate = DateTime.now().subtract(const Duration(days: 180));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final dateStr = '${sinceDate.day.toString().padLeft(2, '0')}-${months[sinceDate.month - 1]}-${sinceDate.year}';
      
      // Tiêu chuẩn hóa chuỗi tìm kiếm IMAP
      final searchCriteria = 'FROM "$expectedSender" SINCE $dateStr';
      
      print('[SalaryService] Using safe search: $searchCriteria');
      var searchResult = await imapClient.uidSearchMessages(searchCriteria: searchCriteria);
      
      final sequence = searchResult.matchingSequence;
      if (sequence == null || sequence.isEmpty) {
        print('[SalaryService] No salary mails found in current search.');
        return [];
      }


      final fetchMeta = await imapClient.uidFetchMessages(sequence, '(UID ENVELOPE)');
      var messages = fetchMeta.messages.toList();
      // Sắp xếp UID giảm dần (mới nhất lên đầu)
      messages.sort((a, b) => (b.uid ?? 0).compareTo(a.uid ?? 0));

      final results = <SalaryRecord>[];
      final maxToProcess = lastProcessedUid == null ? 6 : 10;
      var processedCount = 0;

      for (final msg in messages) {
        if (processedCount >= maxToProcess) break;
        
        final uid = msg.uid ?? 0;
        if (lastProcessedUid != null && uid <= lastProcessedUid) {
          print('[SalaryService] UID $uid already processed, stopping');
          break;
        }

        final subject = msg.envelope?.subject ?? '';
        final emailDate = msg.envelope?.date ?? DateTime.now();
        
        print('[SalaryService] Processing mail UID $uid: $subject');
        
        final fullFetch = await imapClient.uidFetchMessages(
          MessageSequence.fromId(uid, isUid: true), 
          'BODY.PEEK[]'
        );
        final fullMessage = fullFetch.messages.first;
        
        // Thu thập kết quả từ mọi nguồn (frames + body) rồi mới gộp lại theo tháng
        final Map<String, String?> salariesFound = {};
        final Map<String, String?> leavesFound = {};

        // 1. Quét các ảnh đính kèm (bao gồm cả TIFF nhiều trang)
        final allImages = _findAllImageAttachments(fullMessage);
        if (allImages.isNotEmpty) {
          print('[SalaryService] Found ${allImages.length} images, OCRing in PARALLEL...');
          
          final List<Future<void>> ocrTasks = [];
          
          for (final rawImage in allImages) {
            // Giải nén ảnh (Không song song để tránh tốn RAM đột ngột)
            final decodedImage = img.decodeImage(rawImage);
            if (decodedImage == null) continue;

            for (final frame in decodedImage.frames) {
              ocrTasks.add((() async {
                // TỐI ƯU 2: Resize ảnh nếu quá lớn (> 1200px) để OCR nhanh hơn
                img.Image processedImg = frame;
                if (frame.width > 1200) {
                  processedImg = img.copyResize(frame, width: 1200);
                }
                
                final jpgBytes = Uint8List.fromList(img.encodeJpg(processedImg, quality: 85));
                final imageFile = await _saveTempImage(jpgBytes);
                
                try {
                  final ocrResult = await _ocrExtract(imageFile);
                  if (ocrResult != null) {
                    // Xác định tháng của frame này
                    String? fMon;
                    if (subject.toUpperCase().contains('13')) fMon = _findSalaryMonthInText(subject);
                    fMon ??= _findSalaryMonthInText(ocrResult.rawText) ?? _findSalaryMonthInText(subject) ?? '--';
                    
                    if (ocrResult.salary != null) salariesFound[fMon] = ocrResult.salary;
                    if (ocrResult.remainingLeave != null) leavesFound[fMon] = ocrResult.remainingLeave;
                    
                    print('[SalaryService] UID $uid Frame OCR Done: month=$fMon salary=${ocrResult.salary}');
                  }
                } catch (e) {
                  print('[SalaryService] Error in OCR parallel task: $e');
                } finally {
                  await imageFile.delete().catchError((_) => imageFile);
                }
              })());
            }
          }
          
          // Chạy song song tất cả các trang
          await Future.wait(ocrTasks);
        }

        // 2. Quét cả nội dung chữ trong Body mail
        final bodyText = _extractFullText(fullMessage);
        if (bodyText.trim().isNotEmpty) {
          String? bMon;
          if (subject.toUpperCase().contains('13')) bMon = _findSalaryMonthInText(subject);
          bMon ??= _findSalaryMonthInText(bodyText) ?? _findSalaryMonthInText(subject) ?? '--';
          
          final bSal = _extractNetSalary(bodyText);
          final bLev = _extractRemainingLeave(bodyText);
          if (bSal != null) salariesFound[bMon] = bSal;
          if (bLev != null) leavesFound[bMon] = bLev;
        }

        // 3. Hợp nhất các kết quả tìm thấy trong email này
        final allMonthsFound = {...salariesFound.keys, ...leavesFound.keys};
        final Map<String, SalaryRecord> mailRecords = {};
        
        for (final m in allMonthsFound) {
          if (m == '--') continue;
          final s = salariesFound[m];
          final l = leavesFound[m];
          
          if (s != null || l != null) {
            // Chỉ ép về 0 nếu thực sự là tháng 13 hoặc 14
            final isBonus = RegExp(r'Tháng\s+1[34]/', caseSensitive: false).hasMatch(m);
            mailRecords[m] = SalaryRecord(
              salaryMonth: m,
              netSalary: s ?? '--',
              remainingLeave: isBonus ? '--' : (l ?? '--'),
              emailDate: emailDate,
              mailUid: uid,
            );
          }
        }

        if (mailRecords.isNotEmpty) {
          results.addAll(mailRecords.values);
          processedCount++;
          print('[SalaryService] √ Combined UID $uid: ${mailRecords.keys.join(", ")}');
        } else {
          print('[SalaryService] ✗ No data extracted from UID $uid');
        }
      }

      print('[SalaryService] === DONE: ${results.length} total records ===');
      return results;

    } catch (e) {
      print('[SalaryService] Error in fetchSalaryFromMail: $e');
      rethrow;
    } finally {
      if (connected) {
        try { await imapClient.logout(); } catch (_) {}
      }
    }
  }

  // ===== CÁC HÀM HỖ TRỢ =====

  List<Uint8List> _findAllImageAttachments(MimeMessage message) {
    final images = <Uint8List>[];
    _findImageParts(message, images);
    return images;
  }

  void _findImageParts(MimePart part, List<Uint8List> images) {
    if (part.mediaType.top == MediaToptype.image) {
      final content = part.decodeContentBinary();
      if (content != null) {
        images.add(content);
        print('[Image] Found image: type=${part.mediaType}, file=${part.decodeFileName()}, size=${content.length}');
      }
    }
    if (part.parts != null) {
      for (var subPart in part.parts!) {
        _findImageParts(subPart, images);
      }
    }
  }

  String _extractFullText(MimePart part) {
    var text = '';
    if (part.mediaType.top == MediaToptype.text) {
      text += (part.decodeTextPlainPart() ?? part.decodeTextHtmlPart() ?? '');
    }
    if (part.parts != null) {
      for (var subPart in part.parts!) {
        text += _extractFullText(subPart);
      }
    }
    return text;
  }

  Future<File> _saveTempImage(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<OCRResult?> _ocrExtract(File imageFile) async {
    final textRecognizer = GoogleMlKit.vision.textRecognizer();
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      // Ghép văn bản thành các dòng dựa trên tọa độ Y để xử lý bảng tốt hơn
      final fullText = _reconstructLines(recognizedText);
      
      print('=== OCR FULL TEXT DUMP START ===');
      print(fullText);
      print('=== OCR FULL TEXT DUMP END ===');
      
      print('[SalaryService] Reconstructed Table Text:\n$fullText');

      return OCRResult(
        salary: _extractNetSalary(fullText),
        remainingLeave: _extractRemainingLeave(fullText),
        rawText: fullText,
      );
    } catch (e) {
      print('[SalaryService] OCR Error: $e');
      return null;
    } finally {
      textRecognizer.close();
    }
  }

  String _reconstructLines(RecognizedText recognizedText) {
    // Thu thập tất cả các dòng từ tất cả các block
    final allLines = <TextLine>[];
    for (var block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    if (allLines.isEmpty) return "";

    // Sắp xếp các dòng theo tọa độ Y (top)
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // Gom nhóm các dòng thuộc cùng một hàng (Y-tolerance khoảng 25 pixels)
    final rows = <List<TextLine>>[];
    if (allLines.isNotEmpty) {
      rows.add([allLines.first]);
      for (int i = 1; i < allLines.length; i++) {
        final currentLine = allLines[i];
        final lastRow = rows.last;
        final lastLineInRow = lastRow.last;
        
        // Nếu độ lệnh Y nhỏ, coi như cùng 1 hàng
        if ((currentLine.boundingBox.top - lastLineInRow.boundingBox.top).abs() < 25) {
          lastRow.add(currentLine);
        } else {
          rows.add([currentLine]);
        }
      }
    }

    final StringBuffer buffer = StringBuffer();
    for (var row in rows) {
      // Trong mỗi hàng, sắp xếp theo X (left) từ trái sang phải
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      
      // Nối các đoạn text trong cùng hàng bằng dấu cách
      final lineText = row.map((l) => l.text).join(" ");
      buffer.writeln(lineText);
    }

    return buffer.toString();
  }

  // ===== LOGIC TRÍCH XUẤT BẰNG REGEX =====

  String? _findSalaryMonthInText(String text) {
    print('[SalaryService] Identifying month in: ${text.length > 100 ? text.substring(0, 100) + "..." : text}');
    // Ưu tiên format "Tháng 13" - có thể là "T13" hoặc "Tháng 13"
    final m13Match = RegExp(r'(?:TH[AÁ]NG|T|T\.)\s*13[\s\-/\.]*(\d{4})', caseSensitive: false).firstMatch(text);
    if (m13Match != null) return 'Tháng 13/${m13Match.group(1)}';

    final monthPatterns = [
      RegExp(r'L[UƯ]ONG\s+(?:THANG|THÁNG|T|T\.)?\s*(\d{1,2})\s*[\-\/\.]\s*(\d{4})', caseSensitive: false),
      RegExp(r'PHI[ÊEUÚ]+\s+L[UƯ]ONG\s+(?:THANG|THÁNG|T|T\.)?\s*(\d{1,2})\s*[\-\/\.]\s*(\d{4})', caseSensitive: false),
      RegExp(r'T\.?(\d{1,2})[\-\/\.](\d{4})', caseSensitive: false),
      RegExp(r'TH[AÁ]NG\s*(\d{1,2})[\-\/\.](\d{4})', caseSensitive: false),
      RegExp(r'(\d{1,2})[\-\/\.](\d{4})', caseSensitive: false), 
    ];

    for (final pattern in monthPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final m = match.group(1)!.padLeft(2, '0');
        final y = match.group(2)!;
        final monthInt = int.tryParse(m);
        if (monthInt != null && monthInt >= 1 && monthInt <= 12) {
          return 'Tháng $m/$y';
        }
      }
    }
    return null;
  }

  String? _extractNetSalary(String rawText) {
    final lines = rawText.split('\n');
    
    // DEBUG: In từng dòng OCR để kiểm tra nhãn
    print('--- OCR LINE DEBUG START ---');
    for (int i = 0; i < lines.length; i++) {
        print('LINE $i: ${lines[i]}');
    }
    print('--- OCR LINE DEBUG END ---');

    // BƯỚC 1: Tìm dòng chứa từ khóa "LÃNH", "NHẬN", "TRẢ", "THANH TOÁN"
    // Thường là dòng Thực Lãnh
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      // Các từ khóa chỉ dòng tổng thanh toán cuối cùng
      final isFinalRow = lower.contains('thực lãnh') || lower.contains('thuc lanh') || 
                         lower.contains('thực nhận') || lower.contains('thuc nhan') ||
                         lower.contains('thực trả') || lower.contains('thuc tra') ||
                         ((lower.contains('thanh toán') || lower.contains('thanh tien')) && !lower.contains('thuế'));

      if (isFinalRow) {
        final val = _findLastLargeNumber(line);
        if (val != null && val > 500000) {
          print('[SalaryService] FUZZY SUCCESS: Found final salary ${val.round()} in: $line');
          return NumberFormat.decimalPattern('vi').format(val.round());
        }
      }
    }

    // BƯỚC 2: Fallback cho label "27" (Tháng thường)
    for (final line in lines) {
      if (RegExp(r'(^|\s|\||\[|L)27(\s|\||\.)').hasMatch(line)) {
        final val = _findLastLargeNumber(line);
        if (val != null && val > 2000000) {
          print('[SalaryService] LABEL 27 SUCCESS: Found salary ${val.round()} in: $line');
          return NumberFormat.decimalPattern('vi').format(val.round());
        }
      }
    }

    // BƯỚC 3: Fallback cuối cho Tháng 13 - Lấy số lớn cuối cùng nếu không tìm thấy label
    if (rawText.contains('13')) {
        for (final line in lines.reversed) {
            final val = _findLastLargeNumber(line);
            // Tháng 13 thường > 3 tr
            if (val != null && val > 3000000 && val < 50000000) {
                print('[SalaryService] T13 FALLBACK SUCCESS: Found $val in: $line');
                return NumberFormat.decimalPattern('vi').format(val.round());
            }
        }
    }

    return null;
  }

  double? _findLastLargeNumber(String line) {
    final matches = RegExp(r'([\d.,]{6,})').allMatches(line).toList();
    if (matches.isEmpty) return null;
    return _parseMoneyValue(matches.last.group(1)!);
  }

  double? _parseMoneyValue(String raw) {
    // Loại bỏ hết ký tự không phải số để lấy giá trị nguyên
    final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
    return double.tryParse(digitsOnly);
  }

  String? _extractRemainingLeave(String rawText) {
    final lines = rawText.split('\n');
    
    // Duyệt qua tất cả các dòng tìm "còn" hoặc "phép" và có số nhỏ
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      final hasKeywords = lower.contains('còn') || lower.contains('con') || lower.contains('phép') || lower.contains('phep');
      if (hasKeywords) {
        // Tìm mọi số (bao gồm số thập phân) trên dòng đó
        final matches = RegExp(r'(\d+[\s,.]*\d*)').allMatches(line).toList();
        for (final m in matches.reversed) {
            final val = _parseLeaveNumber(m.group(1)!);
            // Số phép năm thường 0-25. 
            // Đặc biệt né số 13, 14 nếu là phiếu tháng 13
            if (val != null && val >= 0 && val < 40) {
                if ((val == 13 || val == 14) && (rawText.contains('tháng 13') || rawText.contains('tháng 14'))) continue;
                print('[SalaryService] FUZZY LEAVE SUCCESS: Found $val in: $line');
                return _formatLeave(val);
            }
        }
      }
    }
    return null;
  }

  double? _parseLeaveNumber(String raw) {
    // Loại bỏ dấu cách nếu OCR tách số và dấu phẩy: "9 , 66" -> "9.66"
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  String _formatLeave(double value) {
    if (value == value.toInt().toDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2).replaceAll('.', ',').replaceFirst(RegExp(r',00$'), '').replaceFirst(RegExp(r'0$'), '');
  }
}

class OCRResult {
  final String? salary;
  final String? remainingLeave;
  final String rawText;

  OCRResult({this.salary, this.remainingLeave, required this.rawText});
}
