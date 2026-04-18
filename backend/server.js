require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const pool = require('./db');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../frontend')));

// ── Create a new exam session ──────────────────────────
app.post('/session', async (req, res) => {
  const { subject, duration_minutes = 30 } = req.body;
  if (!subject) return res.status(400).json({ error: 'subject is required' });

  const now = new Date();
  const dateStr = now.toISOString().split('T')[0];
  const startTimeStr = now.toTimeString().split(' ')[0];
  const end = new Date(now.getTime() + duration_minutes * 60000);
  const endTimeStr = end.toTimeString().split(' ')[0];

  try {
    const [result] = await pool.query(
      'INSERT INTO exams (exam_name, exam_date, start_time, end_time, status) VALUES (?, ?, ?, ?, ?)',
      [subject, dateStr, startTimeStr, endTimeStr, 'ACTIVE']
    );
    res.json({ id: result.insertId, subject });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Mark attendance using Advanced Stored Procedure ────────────────────────
app.post('/attend', async (req, res) => {
  const { qr_code, exam_id, teacher_id } = req.body;
  if (!qr_code || !exam_id || !teacher_id)
    return res.status(400).json({ error: 'qr_code, exam_id, and teacher_id are required' });

  try {
    // 1. Call the stored procedure
    await pool.query('CALL MarkAttendance(?, ?, ?, @msg, @name, @enroll)', [qr_code, exam_id, teacher_id]);
    
    // 2. Fetch the OUT parameters
    const [[output]] = await pool.query('SELECT @msg AS message, @name AS student_name, @enroll AS enrollment;');

    if (output.message && output.message.startsWith('Error:')) {
      return res.status(400).json({ error: output.message });
    }
    if (output.message && output.message.startsWith('Warning:')) {
       return res.status(400).json({ error: output.message }); // Duplicate marks or other warnings
    }

    res.json({ success: true, message: output.message, student_name: output.student_name });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── List all exams ───────────────────────────────────────────────────
app.get('/sessions', async (_req, res) => {
  const [rows] = await pool.query('SELECT exam_id AS id, exam_name AS subject, status, exam_date, start_time, end_time FROM exams ORDER BY exam_date DESC, start_time DESC');
  res.json(rows);
});

// ── Get ALL students with their attendance status for an exam ───
app.get('/records/all/:exam_id', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT s.student_id, s.name, s.email, a.status, a.marked_at
       FROM students s
       LEFT JOIN attendance a ON s.student_id = a.student_id AND a.exam_id = ?
       ORDER BY s.name`,
      [req.params.exam_id]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Get all students ────────────────────────────────────────────────────
app.get('/students', async (_req, res) => {
  const [rows] = await pool.query('SELECT * FROM students ORDER BY name');
  res.json(rows);
});

// ── Get student by Enrollment Number (Login verification) ───────────────
app.get('/student/login/:enrollment_number', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT student_id, name, qr_code_text FROM students WHERE enrollment_number = ?', [req.params.enrollment_number]);
    if (rows.length === 0) return res.status(404).json({ error: 'Student Enrollment Number not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Teacher Authentication ────────────────────────────────────────────────
app.post('/teacher/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const [rows] = await pool.query('SELECT teacher_id, name FROM teachers WHERE email = ? AND password_hash = ?', [email, password]);
    if (rows.length === 0) return res.status(401).json({ error: 'Invalid credentials' });
    res.json({ success: true, teacher_id: rows[0].teacher_id, name: rows[0].name }); 
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Delete Exam (Cascades attendance) ──────────────────────────────────
app.delete('/session/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM exams WHERE exam_id = ?', [req.params.id]);
    res.json({ success: true, message: 'Exam deleted successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Get Active Exams (For Students) ────────────────────────────────────
app.get('/sessions/active', async (_req, res) => {
  try {
    const [rows] = await pool.query("SELECT exam_id AS id, exam_name AS subject FROM exams WHERE status = 'ACTIVE' ORDER BY exam_date DESC, start_time DESC");
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Server running on http://localhost:${port}`));
