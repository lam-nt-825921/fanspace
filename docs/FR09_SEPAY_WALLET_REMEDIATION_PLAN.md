# Danh sách Lỗi & Hạng mục Cần Sửa Đổi — SePay Webhook & Loại bỏ Wallet

> **Mục đích**: Tài liệu tổng hợp các lỗ hổng kỹ thuật, code dư và thiếu sót kiểm thử được phát hiện trong quá trình rà soát chức năng thanh toán SePay (FR-09) để triển khai sửa đổi ở phiên làm việc tiếp theo. *(Không đưa vào tài liệu SRS).*

---

## 1. Gỡ bỏ hoàn toàn tính năng `Wallet` (đã chốt không làm)

Tính năng Ví xu nội bộ (`Wallet` / `coin_balance` / `locked_balance`) không nằm trong phạm vi triển khai nhưng vẫn còn model, khởi tạo tự động khi đăng ký và các field API/Frontend dư thừa.

### Các vị trí cần xóa / dọn dẹp
- **Backend Models & Exports**:
  - `fanspace/backend/app/modules/billing/models.py` (dòng 20–39): Xóa class `Wallet`.
  - `fanspace/backend/app/models/__init__.py` (dòng 4, 24): Xóa import và export `Wallet`.
  - `fanspace/backend/app/modules/identity/models.py` (dòng 61, 100): Xóa docstring và relationship `User.wallet`.
- **Backend Identity Service / Router / Schemas**:
  - `fanspace/backend/app/modules/identity/service.py` (dòng 35, 181, 233, 246–247, 279, 328, 387, 509, 548, 558, 614–615, 647, 994): Xóa import `Wallet`, dừng tạo `Wallet(user_id=user.id, coin_balance=0)` khi verify OTP / Google OAuth, và xóa `selectinload(User.wallet)` / `db.refresh(user, ["wallet"])`.
  - `fanspace/backend/app/modules/identity/router.py` (dòng 78, 438): Xóa `coin_balance=...` khỏi serializer và cập nhật docstring.
  - `fanspace/backend/app/modules/identity/schemas.py` (dòng 202): Xóa field `coin_balance`.
  -*(Tùy chọn dọn cột/bảng)*: Kiểm tra và có thể dọn `allow_coins_payment` trong `fandom/models.py` & `price_coins` trong `rbac/models.py` nếu không dùng; với PostgreSQL local/Docker hiện có thể chạy `DROP TABLE IF EXISTS wallets CASCADE;` hoặc reset volume.
- **Backend Tests**:
  - `fanspace/backend/tests/integration/core/test_infrastructure.py` (dòng 74): Xóa/cập nhật assertion `me_data["coin_balance"]`.
  - `fanspace/backend/tests/integration/auth/test_user_profile.py` (dòng 123, 211): Cập nhật comment và assertion `coin_balance`.
  - `fanspace/backend/tests/integration/auth/test_register.py` (dòng 70, 83): Xóa/cập nhật assertion `v_data["user"]["coin_balance"]`.
- **Frontend**:
  - `fanspace/frontend/lib/models/user_model.dart` (dòng 44, 62): Xóa `coinBalance` khỏi `UserModel` (`fromJson` / `toJson`).
  - `fanspace/frontend/test/unit/auth/user_and_session_model_test.dart` (dòng 18): Cập nhật fixture test không còn `coin_balance`.

---

## 2. Xử lý `IntegrityError` khi 2 webhook trùng `sepay_transaction_id` đến cùng lúc (tránh HTTP 500)

- **File liên quan**: `fanspace/backend/app/modules/billing/service.py` — hàm `BillingService.process_sepay_webhook` (dòng 574–707).
- **Vấn đề hiện tại**:
  - Khi 2 request webhook giống hệt nhau (cùng `sepay_transaction_id`) đến cùng mili-giây, cả 2 đều vượt qua bước check `SELECT` ban đầu (dòng 578–583).
  - Sau khi Request A xong và nhả khóa `FOR UPDATE` trên `PaymentOrder`, Request B chạy tới `await db.commit()` (dòng 686) và cố chèn trùng `PaymentTransaction.sepay_transaction_id` (`unique=True`).
  - Database PostgreSQL chặn đúng bằng `UniqueViolationError` -> SQLAlchemy raise `sqlalchemy.exc.IntegrityError`, nhưng tầng Service **chưa catch exception này** nên FastAPI trả về **HTTP 500 Internal Server Error**.
- **Hướng sửa**:
  - Bọc khối ghi transaction và `await db.commit()` trong `try ... except IntegrityError`:
    1. Gọi `await db.rollback()`.
    2. Truy vấn lại `PaymentTransaction` theo `sepay_transaction_id == payload.id`.
    3. Nếu tìm thấy bản ghi của Request A -> trả về `SepayWebhookResponse(success=True, idempotent_replay=True, reconciliation_status=existing_tx.reconciliation_status, ...)` với HTTP `200 OK` (không emit thêm Socket.IO event).
    4. Nếu vẫn không tìm thấy (lỗi toàn vẹn khác) -> re-raise hoặc báo lỗi phù hợp.

---

## 3. Bổ sung Integration Test Giao dịch Đồng thời (`asyncio.gather`) kiểm chứng Mục 1.5

- **File đề xuất**: `fanspace/backend/tests/integration/billing/test_sepay_concurrency.py` (hoặc bổ sung vào `test_sepay_payment_lifecycle.py`).
- **Vấn đề hiện tại**:
  - Toàn bộ integration test billing hiện chạy **tuần tự**; chưa có test bắn request song song để chứng minh `.with_for_update()` và idempotency chịu tải đồng thời.
- **Kịch bản cần test**:
  1. **2+ webhook trùng `sepay_transaction_id` bắn đồng thời bằng `asyncio.gather`**:
     - Cả 2 request đều trả `200 OK` (không `500`), đúng 1 request có `idempotent_replay=False` và các request còn lại trả `idempotent_replay=True`.
     - Trong DB chỉ tồn tại duy nhất 1 bản ghi `PaymentTransaction`, `order.paid_amount_vnd` chỉ tính 1 lần và `MemberRole.expires_at` không bị gia hạn đúp.
  2. **Nhiều webhook khác `sepay_transaction_id` chuyển tiền đồng thời vào cùng 1 `PaymentOrder`** (ví dụ 2 chuyển khoản 40.000đ + 60.000đ bắn cùng lúc):
     - Tổng `order.paid_amount_vnd` sau khi cả 2 hoàn tất phải đúng bằng `100.000đ` (không bị lost update), trạng thái đơn chuyển sang `PAID`, và vai trò VIP được kích hoạt đúng 1 lần.

---

## 4. Gia cố Bảo mật Endpoint Giả lập & Webhook Secret SePay

- **Khóa endpoint giả lập `/api/v1/billing/sepay-simulate`**:
  - **File**: `fanspace/backend/app/modules/billing/router.py` (dòng 258–270).
  - **Vấn đề**: Hiện chỉ kiểm tra `Depends(get_current_user)` — mọi user đăng nhập đều gọi được ở bất kỳ môi trường nào và kích hoạt trực tiếp `process_sepay_webhook` mà không cần chữ ký SePay.
  - **Hướng sửa**: Chặn endpoint trả về `403`/`404` khi `settings.ENVIRONMENT.lower() == "production"` hoặc `not settings.DEBUG` (nếu giữ lại cho demo nội bộ thì nên yêu cầu thêm điều kiện môi trường dev/staging hoặc quyền owner/admin).
- **Bảo mật `SEPAY_WEBHOOK_SECRET`**:
  - **Files**: `fanspace/backend/app/core/config.py` (dòng 74), `fanspace/backend/.env.example`.
  - **Vấn đề**: `config.py` đang gán cứng default `"sepay_fanspace_secret_2026"` và `.env.example` chưa liệt kê biến `SEPAY_WEBHOOK_SECRET`.
  - **Hướng sửa**: Thêm nhóm biến cấu hình SePay (`SEPAY_WEBHOOK_SECRET`, `SEPAY_PAYMENT_CODE_PREFIX`, ...) vào `.env.example` với placeholder rõ ràng và kiểm tra/cảnh báo nếu chạy môi trường `production` mà vẫn dùng secret mặc định.
