# QR Attendance System

A full-stack, DBMS-driven web application for managing student exam attendance securely using personalized QR codes.

## Features
- **Advanced MySQL Database**: Uses a fully normalized database (up to 3NF) with Triggers, Views, Stored Procedures, and Cursors to safely manage concurrency and attendance tracking.
- **Teacher Dashboard**: Teachers can create exams, track live student attendance, and use their webcam to scan student QR codes.
- **Student Portal**: Students log in securely using their Enrollment Number to view their unique, database-generated QR code.

## Tech Stack
- **Frontend**: HTML5, Vanilla JS, CSS3, `html5-qrcode` library for scanning.
- **Backend**: Node.js, Express.js
- **Database**: MySQL 8+

---

## 🛠 Project Setup

### 0. Clone the Repository
First, clone the repository to your local machine and navigate into it:
```bash
git clone https://github.com/ShreeGattani/DBMS_Project_2026.git
cd DBMS_Project_2026
```
### 1. Database Configuration
1. Make sure you have **MySQL** installed locally.
2. Log into your local MySQL instance:
   ```bash
   mysql -u root -p
   ```
3. Load the database schema and mock data:
   ```sql
   source database/schema.sql;
   exit;
   ```
4. Navigate to the `backend/` folder and copy the example environment file:
   ```bash
   cd backend
   cp .env.example .env
   ```
5. Open the newly created `.env` file and update it with your actual MySQL database password.

### 2. Loading Dependencies
You can automatically load all dependencies using the provided setup script.

Open your terminal in the root folder and run:
```bash
chmod +x setup.sh
./setup.sh
```
*(Alternatively, you can just navigate to the `backend/` folder and manually run `npm install`).*

### 3. Running the Server
Once your database is configured and dependencies are loaded, start the Node.js server:

```bash
cd backend
npm start
```

Your application will now be running at: **http://localhost:3000**

---

## 🔑 Mock Data Logins
If you used the default `schema.sql` mock data, you can test the application using the following credentials:

**Teacher Portal**
- **Email:** `smith@college.edu`
- **Password:** `hashed_pass_smith`

**Student Portal**
- **Enrollment Number:** `2410110323` (Shree Gattani)
