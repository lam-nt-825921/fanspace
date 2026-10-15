# FanSpace (Hệ sinh thái Mạng xã hội Fandom & Giao tiếp Thời gian thực)

> **Bản mẫu Nghiên cứu Khoa học**: Nền tảng Fandom với Kiến trúc Modular Monolith tối ưu hóa hiệu năng/chi phí ($\text{Concurrency-per-Dollar}$), hỗ trợ tải lớn (10,000 CCU) trên môi trường Heroku.

---

## 🌟 Tính năng Cốt lõi
- **Không gian Fandom Biệt lập**: Quản trị độc lập, phân loại chủ đề, mã mời và xét duyệt gia nhập.
- **Trang Khám phá Công khai (Public Directory)**: Giao diện duyệt Fandom tương tự YouTube.
- **Hệ thống Phân quyền Bitmask RBAC ($O(1)$)**: Phân cấp vai trò (Role Hierarchy), bộ 3 Preset Mod và tùy biến quyền hạn.
- **Kênh Chat Thời gian thực & Write-Behind Buffer**: Socket.IO kết hợp Redis Pub/Sub, hàng đợi Redis Stream gom batch 100 tin ghi vào PostgreSQL (giảm 95% IOPS).
- **Phòng Voice Chat LiveKit WebRTC**: Chế độ Open Mic và Khán đài (Stage Room với hàng đợi Giơ tay trên Redis Sorted Set).
- **Hệ thống Hội viên & Thanh toán Reader App**: Gói Role Membership 1–4 mốc, ví tiền ảo với Pessimistic Lock (`SELECT FOR UPDATE`), liên kết VietQR PayOS Sandbox mở trình duyệt ngoài.

---

## 🛠 Tech Stack
- **Backend**: Python 3.12+, FastAPI (Async ASGI), Socket.IO, SQLAlchemy 2.0 (asyncpg), Alembic, Pydantic v2, orjson.
- **Frontend**: Flutter (Impeller Engine), flutter_bloc / Riverpod, livekit_client, socket_io_client.
- **Database & Cache**: PostgreSQL 16, Redis 7 (Pub/Sub & Write-Behind Buffer).
- **DevOps**: Docker Compose, Heroku Multi-Dyno (Dual-Profile: Demo $15/mo vs Benchmark theo giờ).

---

## 🚀 Khởi chạy Môi trường Local

### 1. Khởi động CSDL & Cache bằng Docker
```bash
docker compose up -d
```

### 2. Khởi chạy Backend API
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```
Truy cập tài liệu API tự động tại: `http://localhost:8000/docs` hoặc kiểm tra trạng thái tại: `http://localhost:8000/health`.

### 3. Khởi chạy Frontend Flutter
```bash
cd frontend
flutter run
```
