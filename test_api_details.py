import requests

def test_api():
    # Login
    login_url = "http://localhost:8000/auth/login"
    login_data = {"username": "maksim", "password": "password"}
    resp = requests.post(login_url, data=login_data)
    if resp.status_code != 200:
        print("Login failed")
        return
    
    token = resp.json()["access_token"]
    student_id = resp.json()["user"]["student_id"]
    headers = {"Authorization": f"Bearer {token}"}
    
    # Get details
    details_url = f"http://localhost:8000/students/{student_id}"
    resp = requests.get(details_url, headers=headers)
    print("Student Details:")
    print(resp.json())

if __name__ == "__main__":
    test_api()
