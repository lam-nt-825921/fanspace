"""Security, Password Cryptography, and JWT Claims Management.

This module encapsulates all cryptographic operations for the FanSpace platform.
It utilizes Argon2id for password hashing and python-jose for encoding and decoding
JSON Web Tokens (JWT) adhering strictly to RFC 7519 standards (including unique `jti` claims).
"""

import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any
from jose import jwt
from passlib.context import CryptContext
from app.core.config import get_settings

settings = get_settings()

pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verifies a plaintext password against an Argon2id hashed password string.

    Args:
        plain_password (str): Candidate plaintext password entered by the user.
        hashed_password (str): Stored Argon2id hash from the database.

    Returns:
        bool: True if the password matches the hash, False otherwise.
    """
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Generates a secure Argon2id hash from a plaintext password string.

    Args:
        password (str): Plaintext password to hash.

    Returns:
        str: Cryptographically salted and stretched Argon2id hash string.
    """
    return pwd_context.hash(password)


def create_access_token(
    data: dict[str, Any],
    expires_delta: timedelta | None = None,
) -> str:
    """Creates a signed JSON Web Access Token.

    Appends expiration time (`exp`), token type (`type='access'`), and a globally
    unique token identifier (`jti`) conforming to RFC 7519.

    Args:
        data (dict[str, Any]): Claims to encode into the token payload (e.g. `sub`, `session_id`).
        expires_delta (timedelta | None, optional): Custom lifespan for the token.
            Defaults to `settings.ACCESS_TOKEN_EXPIRE_MINUTES`.

    Returns:
        str: Encoded and digitally signed JWT string.
    """
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire, "type": "access", "jti": uuid.uuid4().hex})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(
    data: dict[str, Any],
    expires_delta: timedelta | None = None,
) -> str:
    """Creates a signed JSON Web Refresh Token.

    Embeds extended lifespan (`exp`), token type (`type='refresh'`), and a distinct `jti`
    to support single-session validation and Refresh Token Rotation.

    Args:
        data (dict[str, Any]): Claims to encode into the refresh token payload.
        expires_delta (timedelta | None, optional): Custom lifespan for the token.
            Defaults to `settings.REFRESH_TOKEN_EXPIRE_DAYS`.

    Returns:
        str: Encoded and digitally signed JWT refresh token string.
    """
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire, "type": "refresh", "jti": uuid.uuid4().hex})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict[str, Any]:
    """Decodes and validates a JSON Web Token against platform secret key and algorithm.

    Args:
        token (str): Raw JWT string to parse.

    Returns:
        dict[str, Any]: Decoded claims dictionary if the signature is valid and not expired.

    Raises:
        jose.JWTError: If the token has an invalid signature, is malformed, or has expired.
    """
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])


def hash_token(token: str) -> str:
    """Calculates a deterministic SHA-256 hex digest of a token string.

    Used to store refresh tokens in database session records securely without
    persisting plaintext token material.

    Args:
        token (str): Raw JWT or session token string.

    Returns:
        str: 64-character hexadecimal SHA-256 hash.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
