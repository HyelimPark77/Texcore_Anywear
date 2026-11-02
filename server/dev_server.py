"""개발·시연용 서버 실행기. 문자 사업자 대신 인증번호를 이 터미널에 찍어 준다(운영 코드 아님).

    python dev_server.py              # http://127.0.0.1:8000 , 에뮬레이터에서는 http://10.0.2.2:8000
    DEV_HOST=0.0.0.0 python dev_server.py   # 같은 와이파이의 아이폰 실기기에서 접속할 때

- 자문단 승인 전 draft 안전 규칙을 내려보낸다(ALLOW_DRAFT_RULES).
- 데이터는 dev.db(SQLite)에 쌓인다. 처음부터 하려면 이 파일을 지우면 된다.
"""
import os
import socket
import sys
from pathlib import Path

import uvicorn

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app.config import Settings  # noqa: E402
from app.gateway import MemoryGateway  # noqa: E402
from app.main import create_app  # noqa: E402


class ConsoleGateway(MemoryGateway):
    def send(self, msg):
        super().send(msg)
        if msg.channel == "sms":
            print(f"\n  ▶ 인증번호  {msg.to_phone} : {msg.data['code']}\n", flush=True)
        else:
            print(f"  [{msg.channel} → 사용자 {msg.to_user_id}] {msg.title}: {msg.body}", flush=True)


def add_pages(app, base):
    """브라우저로 바로 볼 수 있게: 실제 앱(웹 빌드)은 /app/, 휴대폰 틀은 /phone, HTML 시연은 /demo"""
    from fastapi.responses import FileResponse
    from fastapi.staticfiles import StaticFiles
    web, demo, phone = base / "web", base / "demo.html", base / "phone.html"
    if phone.exists():
        app.get("/phone", include_in_schema=False)(lambda: FileResponse(phone))
    if demo.exists():
        app.get("/demo", include_in_schema=False)(lambda: FileResponse(demo))
    if web.exists():
        app.mount("/app", StaticFiles(directory=web, html=True), name="app")
    return web.exists(), demo.exists()


if __name__ == "__main__":
    db = Path(__file__).resolve().parent / "dev.db"
    app = create_app(Settings(database_url=f"sqlite:///{db}", allow_draft_rules=True), gateway=ConsoleGateway())
    has_app, has_demo = add_pages(app, Path(__file__).resolve().parent.parent)
    print("운동친구 개발 서버 · 에뮬레이터 앱은 http://10.0.2.2:8000 으로 접속합니다")
    if has_app:
        print("  휴대폰 화면(VS Code Simple Browser 추천): http://localhost:8000/phone")
        print("  브라우저에서 실제 앱:   http://localhost:8000/app/")
    if has_demo:
        print("  브라우저에서 HTML 시연: http://localhost:8000/demo")
    # 실기기(아이폰)에서 접속할 때만 DEV_HOST=0.0.0.0 — 같은 와이파이에 열린다(개발용 메모리 서버)
    host = os.environ.get("DEV_HOST", "127.0.0.1")
    if host != "127.0.0.1":
        print(f"  같은 와이파이의 휴대폰 앱은 http://{socket.gethostname().removesuffix('.local')}.local:8000 으로 접속합니다")
    uvicorn.run(app, host=host, port=int(sys.argv[1]) if len(sys.argv) > 1 else 8000, log_level="warning")
