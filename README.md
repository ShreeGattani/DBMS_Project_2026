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
Navigate to the backend folder and install the required Node.js packages:
```bash
cd backend
npm install
```

### 3. Running the Server
Once your database is configured and dependencies are loaded, start the Node.js server:
```bash
cd backend
npm start
```

Your application will now be running at: **http://localhost:3000**

---

##  Mock Data Logins
If you used the default `schema.sql` mock data, you can test the application using the following credentials:

**Teacher Portal**
- **Email:** `smith@college.edu`
- **Password:** `hashed_pass_smith`

**Student Portal**
- **Enrollment Number:** `2410110323` (Shree Gattani)

---

##  Code Structure & Description

### `database/`
- **`schema.sql`**: The heart of the DBMS project. Contains the entirely normalized MySQL relational schema, composite keys, automatic UUID triggers, views for analytics, and transaction-safe stored procedures.

### `backend/`
- **`server.js`**: The main Node.js / Express backend server. It handles REST API routing, authenticates logins, and serves as the middleware connecting the frontend to the MySQL stored procedures.
- **`db.js`**: A connection pooling module utilizing `mysql2/promise` to maintain a stable, efficient connection to the local database via environment variables.

### `frontend/`
- **`teacher.html` & `teacher_login.html`**: The invigilator portal. Utilizes the device webcam to scan QR codes and immediately pushes them to the backend API to invoke the `MarkAttendance` SQL procedure.
- **`student.html`**: The student portal where users enter their Enrollment Number to pull down their static, database-generated QR code for scanning.

---

##  References & URLs
- **Node.js**: [https://nodejs.org/](https://nodejs.org/) - JavaScript runtime environment.
- **Express.js**: [https://expressjs.com/](https://expressjs.com/) - Backend web framework.
- **MySQL 8.0**: [https://dev.mysql.com/doc/](https://dev.mysql.com/doc/) - Relational database management system.
- **html5-qrcode**: [https://github.com/mebjas/html5-qrcode](https://github.com/mebjas/html5-qrcode) - The open-source JavaScript library used for reading QR codes via the device camera.
- **dotenv**: [https://www.npmjs.com/package/dotenv](https://www.npmjs.com/package/dotenv) - Zero-dependency module that loads environment variables from a `.env` file into `process.env`.
