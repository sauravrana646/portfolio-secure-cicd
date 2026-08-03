from app.main import create_app


def test_healthz():
    client = create_app().test_client()
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.get_json()["status"] == "ok"


def test_root():
    client = create_app().test_client()
    res = client.get("/")
    assert res.status_code == 200
    assert res.get_json()["service"] == "portfolio-secure-cicd"
