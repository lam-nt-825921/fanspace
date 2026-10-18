import logging
from email.message import EmailMessage
import aiosmtplib

from app.core.config import get_settings

logger = logging.getLogger("fanspace.mailer")
settings = get_settings()


async def send_otp_email(to_email: str, otp: str, purpose_label: str = "Xác thực tài khoản"):
    """
    Sends an OTP verification email asynchronously via SMTP (e.g. Gmail).
    Falls back to console logging in development or if SMTP is not configured.
    """
    subject = f"[FanSpace] Mã xác thực OTP: {otp}"

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0F172A; color: #F8FAFC; padding: 24px; }}
        .card {{ max-width: 500px; margin: 0 auto; background: #1E293B; border-radius: 12px; padding: 32px; border: 1px solid #334155; }}
        .header {{ font-size: 24px; font-weight: 700; color: #38BDF8; margin-bottom: 8px; }}
        .otp-box {{ background: #0F172A; border: 2px dashed #38BDF8; border-radius: 8px; padding: 16px; text-align: center; font-size: 36px; font-weight: 800; letter-spacing: 6px; color: #38BDF8; margin: 24px 0; }}
        .footer {{ font-size: 13px; color: #94A3B8; margin-top: 24px; border-top: 1px solid #334155; padding-top: 16px; }}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="header">FanSpace - {purpose_label}</div>
        <p>Xin chào,</p>
        <p>Bạn đang thực hiện thao tác <strong>{purpose_label}</strong> trên FanSpace. Mã OTP xác thực của bạn là:</p>
        <div class="otp-box">{otp}</div>
        <p>Mã này có hiệu lực trong vòng <strong>5 phút</strong>. Không chia sẻ mã này với bất kỳ ai để bảo vệ an toàn cho tài khoản.</p>
        <div class="footer">Nếu bạn không yêu cầu mã này, vui lòng bỏ qua email. Đây là email tự động, vui lòng không trả lời.</div>
      </div>
    </body>
    </html>
    """

    # Always log to console in dev
    logger.info(f"===> [EMAIL OTP] To: {to_email} | Purpose: {purpose_label} | OTP: {otp} <===")
    print(f"\n==========================================")
    print(f"📧 [FanSpace EMAIL OTP]")
    print(f"To: {to_email}")
    print(f"Mục đích: {purpose_label}")
    print(f"MÃ OTP: {otp} (Hiệu lực 5 phút)")
    print(f"==========================================\n")

    if not settings.SMTP_USER or not settings.SMTP_PASSWORD:
        logger.warning("SMTP credentials not configured. Email logged to console only.")
        return

    message = EmailMessage()
    message["From"] = f"{settings.EMAILS_FROM_NAME} <{settings.EMAILS_FROM_EMAIL or settings.SMTP_USER}>"
    message["To"] = to_email
    message["Subject"] = subject
    message.set_content(f"Mã OTP xác thực FanSpace của bạn là: {otp}. Mã có hiệu lực trong 5 phút.")
    message.add_alternative(html_content, subtype="html")

    try:
        await aiosmtplib.send(
            message,
            hostname=settings.SMTP_HOST,
            port=settings.SMTP_PORT,
            start_tls=True,
            username=settings.SMTP_USER,
            password=settings.SMTP_PASSWORD,
            timeout=10.0,
        )
        logger.info(f"Successfully sent OTP email to {to_email} via Gmail SMTP.")
    except Exception as e:
        logger.error(f"Failed to send email via SMTP to {to_email}: {str(e)}")
        # Do not raise error to client in dev, log it
