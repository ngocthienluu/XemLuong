import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'salary_service.dart';
import 'salary_storage.dart';

void main() => runApp(const XemLuongApp());

class XemLuongApp extends StatelessWidget {
  const XemLuongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xem Lương',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00D9A6),
          surface: Color(0xFF1A1F38),
        ),
      ),
      home: const SalaryHomePage(),
    );
  }
}

class SalaryHomePage extends StatefulWidget {
  const SalaryHomePage({super.key});

  @override
  State<SalaryHomePage> createState() => _SalaryHomePageState();
}

class _SalaryHomePageState extends State<SalaryHomePage>
    with SingleTickerProviderStateMixin {
  final SalaryService _service = SalaryService();
  final SalaryStorage _storage = SalaryStorage();

  SalaryRecord? _currentRecord;
  List<SalaryRecord> _history = [];
  bool _isLoading = false;
  String _statusMessage = '';
  bool _hasError = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadCachedThenFetch();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Load cache → hiện ngay → Chỉ fetch khi cần
  Future<void> _loadCachedThenFetch() async {
    // Bước 1: Load từ cache (nhanh)
    final history = await _storage.loadHistory();
    if (history.isNotEmpty && mounted) {
      setState(() {
        _history = history;
        _currentRecord = history.first;
        _statusMessage = 'Đã tải từ bộ nhớ tạm';
      });
      // Nếu có sẵn dữ liệu, không tự động fetch mail mới nữa để vào app nhanh hơn
      print('[SalaryHomePage] Loaded ${history.length} records from cache.');
    } else {
      // Nếu chưa có dữ liệu, mới bắt đầu tải mail lần đầu
      await _fetchFromMail();
    }
  }

  Future<void> _fetchFromMail() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _statusMessage = 'Đang tìm phiếu lương mới...';
    });

    try {
      final lastUid = await _storage.getLastProcessedUid();
      final records = await _service.fetchSalaryFromMail(
        lastProcessedUid: lastUid,
      );

      if (records.isNotEmpty) {
        await _storage.saveSalaryRecords(records);
        final allHistory = await _storage.loadHistory();

        if (mounted) {
          setState(() {
            _history = allHistory;
            _currentRecord = allHistory.first;
            _statusMessage = 'Cập nhật ${records.length} phiếu lương • ${DateFormat('HH:mm').format(DateTime.now())}';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            if (_currentRecord != null) {
              _statusMessage = 'Không có phiếu lương mới • ${DateFormat('HH:mm').format(DateTime.now())}';
            } else {
              _statusMessage = 'Không tìm thấy phiếu lương trong mail';
              _hasError = true;
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final msg = e.toString();
          _statusMessage = 'Lỗi: ${msg.length > 60 ? '${msg.substring(0, 60)}...' : msg}';
          _hasError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchFromMail,
          color: const Color(0xFF6C63FF),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildSalaryCard()),
              SliverToBoxAdapter(child: _buildLeaveCard()),
              SliverToBoxAdapter(child: _buildStatusBar()),
              if (_history.length > 1) ...[
                SliverToBoxAdapter(child: _buildHistoryHeader()),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildHistoryItem(_history[index + 1]),
                    childCount: _history.length - 1,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildRefreshFAB(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phiếu Lương',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentRecord?.salaryMonth ?? 'Chưa có dữ liệu',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white.withAlpha(128),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryCard() {
    final hasSalary = _currentRecord != null && _currentRecord!.netSalary != '--';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E2240), Color(0xFF161A33)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF6C63FF).withAlpha(50),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withAlpha(40),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on_rounded, color: Color(0xFF6C63FF), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'THỰC LÃNH',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6C63FF),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Mục 27',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withAlpha(80),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      hasSalary ? _currentRecord!.netSalary : '--',
                      style: GoogleFonts.inter(
                        fontSize: hasSalary ? 40 : 32,
                        fontWeight: FontWeight.w900,
                        color: hasSalary ? Colors.white : Colors.white.withAlpha(80),
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                  ),
                  if (hasSalary) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'VNĐ',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF00D9A6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (hasSalary) ...[
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFF6C63FF).withAlpha(80), Colors.transparent],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _currentRecord!.salaryMonth,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    color: Colors.white.withAlpha(200),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveCard() {
    final hasLeave = _currentRecord != null && _currentRecord!.remainingLeave != '--';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A2435), Color(0xFF141C2E)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00D9A6).withAlpha(40),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D9A6).withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.beach_access_rounded, color: Color(0xFF00D9A6), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phép năm còn lại',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withAlpha(128),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasLeave ? '${_currentRecord!.remainingLeave} ngày' : '--',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: hasLeave ? const Color(0xFF00D9A6) : Colors.white.withAlpha(80),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    if (_statusMessage.isEmpty && !_isLoading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hasError ? const Color(0xFFFF5252).withAlpha(30) : const Color(0xFF6C63FF).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hasError ? const Color(0xFFFF5252).withAlpha(50) : Colors.transparent),
        ),
        child: Row(
          children: [
            if (_isLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF))))
            else
              Icon(_hasError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 16, color: _hasError ? const Color(0xFFFF5252) : const Color(0xFF00D9A6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusMessage,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withAlpha(150)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Text('Lịch sử lương', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          Text('${_history.length - 1} tháng trước', style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withAlpha(100))),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(SalaryRecord record) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141828),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(10)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.salaryMonth, style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withAlpha(128))),
                    const SizedBox(height: 2),
                    Text('${record.netSalary} VNĐ', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Phép', style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withAlpha(80))),
                  Text(record.remainingLeave, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF00D9A6))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshFAB() {
    return FloatingActionButton(
      onPressed: _isLoading ? null : _fetchFromMail,
      backgroundColor: const Color(0xFF6C63FF),
      child: _isLoading
          ? const Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 10),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ],
            )
          : const Icon(Icons.refresh_rounded, color: Colors.white, size: 28),
    );
  }
}
