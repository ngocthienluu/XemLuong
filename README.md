# 💰 XemLuong - Giải Pháp Theo Dõi Thu Nhập Tự Động Từ Email

![XemLuong Logo](assets/images/logo.png)

**XemLuong** là ứng dụng di động được phát triển bằng Flutter, giúp người dùng tự động hóa việc quản lý và theo dõi lịch sử lương hàng tháng. Thay vì phải lục tìm email và tải file thủ công, XemLuong sẽ tự động quét hòm thư, sử dụng trí tuệ nhân tạo (OCR) để trích xuất dữ liệu và hiển thị lên một giao diện hiện đại, chuyên nghiệp.

---

## ✨ Tính năng chính

### 📥 1. Tự Động Kết Nối & Quét Email
- Kết nối bảo mật tới Gmail thông qua giao thức **IMAP**.
- Tìm kiếm thông minh các email từ nhà tuyển dụng/công ty (dựa trên địa chỉ người gửi được cấu hình).
- Tự động lọc các email có tiêu đề liên quan đến "Lương" hoặc "Salary".

### 🔎 2. Trích Xuất Dữ Liệu AI (OCR)
- Sử dụng **Google ML Kit Text Recognition** để đọc nội dung từ:
  - Ảnh đính kèm (JPG, PNG).
  - Các file ảnh định dạng **TIFF** nhiều trang (thường gặp trong hệ thống quản lý lương doanh nghiệp).
- Thuật toán thông minh tự động nhận diện:
  - **Tháng lương**: Phân biệt chính xác tháng thường và tháng thưởng (Tháng 13/14).
  - **Thực lãnh (Net Salary)**: Tự động tìm kiếm con số tổng thanh toán cuối cùng.
  - **Phép năm còn lại**: Trích xuất số ngày phép chưa sử dụng.

### 📊 3. Quản Lý Lịch Sử Tiền Lương
- Lưu trữ toàn bộ dữ liệu vào bộ nhớ máy (**Shared Preferences**), cho phép truy cập ngay lập tức kể cả khi không có mạng.
- Giao diện danh sách lịch sử theo thời gian, giúp bạn dễ dàng so sánh thu nhập giữa các tháng.

### 🎨 4. Trải Nghiệm Người Dùng (UX/UI) Cao Cấp
- **Chế độ Dark Mode**: Giao diện tối huyền bí, sang trọng và bảo vệ mắt.
- **Micro-Animations**: Các hiệu ứng chuyển động mượt mà, Pulse animations khi đang tải dữ liệu.
- **Responsive Design**: Tự động hiển thị đẹp mắt trên mọi kích thước màn hình điện thoại.

---

## 🛠 Công nghệ & Thư viện sử dụng

| Công nghệ | Mục đích |
| :--- | :--- |
| **Flutter 3.x** | Framework chính để phát triển ứng dụng Cross-platform. |
| **Google ML Kit** | Xử lý OCR (Nhận diện văn bản từ hình ảnh) mạnh mẽ. |
| **Enough Mail** | Xử lý giao thức IMAP an toàn và hiệu quả cao. |
| **Image (Dart)** | Giải mã hình ảnh, xử lý các file TIFF phức tạp. |
| **Google Fonts** | Phông chữ `Inter` chuyên nghiệp và hiện đại. |
| **Shared Preferences** | Lưu trữ dữ liệu lịch sử bền vững trên thiết bị. |

---

## 🚀 Hướng Dẫn Cài Đặt & Chạy

### 1. Yêu cầu hệ thống
- **Flutter SDK**: `>=3.6.2`
- **Android SDK**: `Level 35` (Yêu cầu để tương thích với ML Kit mới nhất).
- **Thiết bị**: Android 6.0+ trở lên.

### 2. Chuẩn bị tài khoản Gmail
Để ứng dụng có thể đọc mail, bạn cần:
1.  Bật **Xác minh 2 bước** trên tài khoản Google.
2.  Tạo **Mật khẩu ứng dụng (App Password)**:
    - Truy cập [My Account Google](https://myaccount.google.com/apppasswords).
    - Chọn "Mail" và "Trình thiết bị: Khác".
    - Lưu lại chuỗi 16 ký tự được cung cấp.

### 3. Cấu hình Code
Mở file `lib/salary_service.dart` và cập nhật thông tin sau:
```dart
static const String mailEmail = 'tandungluu338@gmail.com'; // Email của bạn
static const String mailPassword = 'your-app-password';     // Mật khẩu ứng dụng 16 ký tự
static const String expectedSender = 'lg.la@tpgroup.com.vn'; // Email người gửi phiếu lương
```

### 4. Lệnh Build
```bash
# Lấy các dependencies
flutter pub get

# Chạy ở chế độ Debug
flutter run

# Tạo file APK để cài đặt
flutter build apk --debug
```

---

## 🛡 Xử lý bảo mật & Quyền riêng tư
- **Không lưu mật khẩu chính**: Ứng dụng khuyên dùng App Password để bảo vệ tài khoản Gmail.
- **Dữ liệu cục bộ**: Toàn bộ lịch sử lương chỉ được lưu trên thiết bị của bạn, không được gửi đi bất kỳ máy chủ nào khác.
- **OCR On-Device**: Việc nhận diện hình ảnh diễn ra ngay trên điện thoại, không thông qua API đám mây nhằm đảm bảo tính riêng tư.

---

## 📝 Nhật ký cập nhật gần đây
- ✅ **Version 1.1**: Sửa lỗi hiển thị phép năm ở Tháng 13/14 (hiển thị `--` để tránh sai sót).
- ✅ **Version 1.0**: Hoàn thiện tính năng quét OCR từ file TIFF nhiều trang.
- ✅ **UI Update**: Thêm hiệu ứng Glassmorphism cho các thẻ hiển thị thu nhập.

---

## 📧 Liên hệ
- **Tác giả**: [ngocthienluu](https://github.com/ngocthienluu)
- **Email hỗ trợ**: [tandungluu338@gmail.com]

---
*Phát triển bởi Antigravity AI với sự phối hợp cùng người dùng.*
