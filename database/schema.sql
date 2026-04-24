-- -----------------------------------------------------------------------------
-- ADVANCED DBMS PROJECT SCHEMA: QR ATTENDANCE SYSTEM
-- This script contains Normalized Tables (up to 3NF), Foreign Key Constraints,
-- Views, Triggers, Stored Procedures, Functions, Cursors, and Transactions.
-- -----------------------------------------------------------------------------

DROP DATABASE IF EXISTS qr_attendance_db;
CREATE DATABASE qr_attendance_db;
USE qr_attendance_db;

CREATE TABLE teachers (
    teacher_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE students (
    student_id INT AUTO_INCREMENT PRIMARY KEY,
    enrollment_number VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    qr_code_text VARCHAR(255) UNIQUE, -- Will be auto-generated later via TRIGGER
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE exams (
    exam_id INT AUTO_INCREMENT PRIMARY KEY,
    exam_name VARCHAR(100) NOT NULL,
    exam_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    status ENUM('UPCOMING', 'ACTIVE', 'COMPLETED') DEFAULT 'UPCOMING'
);

CREATE TABLE exam_invigilators (
    exam_id INT,
    teacher_id INT,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (exam_id, teacher_id),
    FOREIGN KEY (exam_id) REFERENCES exams(exam_id) ON DELETE CASCADE,
    FOREIGN KEY (teacher_id) REFERENCES teachers(teacher_id) ON DELETE CASCADE
);

CREATE TABLE attendance (
    attendance_id INT AUTO_INCREMENT PRIMARY KEY,
    exam_id INT,
    student_id INT,
    marked_by_teacher_id INT,
    status ENUM('PRESENT', 'ABSENT') DEFAULT 'ABSENT',
    marked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    remarks VARCHAR(255),
    FOREIGN KEY (exam_id) REFERENCES exams(exam_id) ON DELETE CASCADE,
    FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE,
    FOREIGN KEY (marked_by_teacher_id) REFERENCES teachers(teacher_id) ON DELETE SET NULL,
    UNIQUE (exam_id, student_id) -- A student can only have one attendance record per exam
);

CREATE TABLE audit_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    action_type VARCHAR(50),
    description TEXT,
    logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- =============================================================================
-- 2. ADVANCED VIEWS (For Read-Optimized Queries)
-- =============================================================================

-- View: vw_exam_attendance_summary 
-- Summarizes how many students are present vs absent per exam.
CREATE VIEW vw_exam_attendance_summary AS
SELECT 
    e.exam_id, 
    e.exam_name,
    COUNT(a.student_id) AS total_enrolled,
    SUM(CASE WHEN a.status = 'PRESENT' THEN 1 ELSE 0 END) AS total_present,
    SUM(CASE WHEN a.status = 'ABSENT' THEN 1 ELSE 0 END) AS total_absent
FROM exams e
LEFT JOIN attendance a ON e.exam_id = a.exam_id
GROUP BY e.exam_id, e.exam_name;


-- =============================================================================
-- 3. TRIGGERS (Automated constraints and logging)
-- =============================================================================

DELIMITER $$

-- Trigger 1: Auto-generate a secure QR text hash BEFORE INSERTing a new student
CREATE TRIGGER trigger_before_student_insert
BEFORE INSERT ON students
FOR EACH ROW
BEGIN
    -- Using UUID instead of SHA1 to avoid built-in function missing error
    IF NEW.qr_code_text IS NULL OR NEW.qr_code_text = '' THEN
        SET NEW.qr_code_text = UUID();
    END IF;
END$$

-- Trigger 2: Log attendance marking in audit table AFTER UPDATE
CREATE TRIGGER trigger_after_attendance_update
AFTER UPDATE ON attendance
FOR EACH ROW
BEGIN
    IF OLD.status != NEW.status AND NEW.status = 'PRESENT' THEN
        INSERT INTO audit_logs (action_type, description)
        VALUES ('ATTENDANCE_MARKED', CONCAT('Student ID ', NEW.student_id, ' marked PRESENT for Exam ID ', NEW.exam_id, ' by Teacher ID ', NEW.marked_by_teacher_id));
    END IF;
END$$

DELIMITER ;


-- =============================================================================
-- 4. SCALAR FUNCTIONS (Calculations on the fly)
-- =============================================================================

DELIMITER $$

-- Function 1: Get single student's overall attendance percentage across all exams
CREATE FUNCTION GetStudentAttendancePercentage(p_student_id INT) 
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE total_classes INT;
    DECLARE attended_classes INT;
    DECLARE percentage DECIMAL(5,2);
    
    SELECT COUNT(*) INTO total_classes FROM attendance WHERE student_id = p_student_id;
    SELECT COUNT(*) INTO attended_classes FROM attendance WHERE student_id = p_student_id AND status = 'PRESENT';
    
    IF total_classes = 0 THEN
        RETURN 0.00;
    ELSE
        SET percentage = (attended_classes / total_classes) * 100;
        RETURN percentage;
    END IF;
END$$

DELIMITER ;


-- =============================================================================
-- 5. STORED PROCEDURES & TRANSACTIONS
-- =============================================================================

DELIMITER $$

-- Procedure 1: MarkAttendance using a Transaction
-- This safely ensures concurrency, prevents race conditions, and prevents duplicate marks.
CREATE PROCEDURE MarkAttendance(
    IN p_qr_code VARCHAR(255),
    IN p_exam_id INT,
    IN p_teacher_id INT,
    OUT p_message VARCHAR(255),
    OUT p_student_name VARCHAR(100),
    OUT p_enrollment VARCHAR(20)
)
BEGIN
    DECLARE v_student_id INT;
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_exam_status VARCHAR(20);
    
    -- Exception Handler explicitly for SQL errors (Rollback on failure)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'Error: Transaction Failed. Rolled back.';
        SET p_student_name = '';
        SET p_enrollment = '';
    END;

    -- Look up student by QR
    SELECT student_id, name, enrollment_number 
    INTO v_student_id, p_student_name, p_enrollment
    FROM students WHERE qr_code_text = p_qr_code LIMIT 1;
    
    IF v_student_id IS NULL THEN
        SET p_message = 'Error: Invalid QR Code.';
    ELSE
        -- Check if the exam is active
        SELECT status INTO v_exam_status FROM exams WHERE exam_id = p_exam_id;
        IF v_exam_status != 'ACTIVE' THEN
            SET p_message = CONCAT('Error: Exam is currently ', v_exam_status);
        ELSE
            -- Start Transaction to safely manage concurrent scans
            START TRANSACTION;
            
            -- Check if already marked present
            SELECT status INTO v_current_status FROM attendance 
            WHERE student_id = v_student_id AND exam_id = p_exam_id FOR UPDATE; 
            
            IF v_current_status = 'PRESENT' THEN
                SET p_message = 'Warning: Student is already marked PRESENT.';
                ROLLBACK;
            ELSE
                IF v_current_status IS NULL THEN
                    INSERT INTO attendance (exam_id, student_id, marked_by_teacher_id, status, marked_at)
                    VALUES (p_exam_id, v_student_id, p_teacher_id, 'PRESENT', CURRENT_TIMESTAMP);
                ELSE
                    -- Safely lock and mark attendance
                    UPDATE attendance 
                    SET status = 'PRESENT', marked_by_teacher_id = p_teacher_id, marked_at = CURRENT_TIMESTAMP
                    WHERE student_id = v_student_id AND exam_id = p_exam_id;
                END IF;
                
                SET p_message = 'Success: Attendance Marked.';
                COMMIT;
            END IF;
            
        END IF;
    END IF;
END$$

DELIMITER ;


-- =============================================================================
-- 6. CURSORS (Advanced Row-By-Row Processing)
-- =============================================================================

DELIMITER $$

-- Procedure 2: GenerateAbsenteesReport using a Cursor
-- Iterates over students in a specific exam who remain absent.
CREATE PROCEDURE GenerateAbsenteesList(IN p_exam_id INT)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE cur_student_id INT;
    DECLARE cur_name VARCHAR(100);
    DECLARE cur_enrollment VARCHAR(20);
    
    -- Declare the Cursor to find students who are 'ABSENT' for the given exam
    DECLARE absentee_cursor CURSOR FOR 
        SELECT s.student_id, s.name, s.enrollment_number 
        FROM attendance a
        JOIN students s ON a.student_id = s.student_id
        WHERE a.exam_id = p_exam_id AND a.status = 'ABSENT';
        
    -- Handle End of Data
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- Create a temporary table to store the results of the cursor
    DROP TEMPORARY TABLE IF EXISTS temp_absentees;
    CREATE TEMPORARY TABLE temp_absentees (
        student_id INT,
        name VARCHAR(100),
        enrollment_number VARCHAR(20)
    );
    
    OPEN absentee_cursor;
    
    -- Loop through cursor row by row
    read_loop: LOOP
        FETCH absentee_cursor INTO cur_student_id, cur_name, cur_enrollment;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Insert logic here (could send emails to parents, for this project we insert into temp table)
        INSERT INTO temp_absentees (student_id, name, enrollment_number) 
        VALUES (cur_student_id, cur_name, cur_enrollment);
    END LOOP;
    
    CLOSE absentee_cursor;
    
    -- Return the result set
    SELECT * FROM temp_absentees;
END$$

DELIMITER ;


-- =============================================================================
-- 7. MOCK DATA (Testing script)
-- =============================================================================

-- Insert Teachers
INSERT INTO teachers (name, email, password_hash) VALUES 
('Professor Smith', 'smith@college.edu', 'hashed_pass_smith'),
('Professor Johnson', 'johnson@college.edu', 'hashed_pass_john');

-- Insert Exams
INSERT INTO exams (exam_name, exam_date, start_time, end_time, status) VALUES 
('DBMS Midterm', '2026-05-10', '10:00:00', '13:00:00', 'ACTIVE'),
('OS Final Exam', '2026-05-15', '14:00:00', '17:00:00', 'UPCOMING');

-- Assign Invigilators
INSERT INTO exam_invigilators (exam_id, teacher_id) VALUES 
(1, 1), (1, 2);

-- Insert Students (QR text generated automatically by Trigger!)
INSERT INTO students (enrollment_number, name, email, password_hash) VALUES
('2410110302', 'SANYA  TRIPATHI', 'sanya@snu.edu.in', 'hashed_pass_tripathi302'),
('2410110304', 'SARANSH', 'saransh@snu.edu.in', 'hashed_pass_saransh304'),
('2410110306', 'SARTHAK  JAIN', 'sarthak@snu.edu.in', 'hashed_pass_jain306'),
('2410110309', 'SATYAM  CHAUHAN', 'satyam@snu.edu.in', 'hashed_pass_chauhan309'),
('2410110315', 'SHARANYA  GUPTA', 'sharanya@snu.edu.in', 'hashed_pass_gupta315'),
('2410110316', 'SHAURYA MITTAL NAIR', 'shaurya.nair@snu.edu.in', 'hashed_pass_nair316'),
('2410110317', 'SHAURYA ANUP SHARMA', 'shaurya.sharma@snu.edu.in', 'hashed_pass_sharma317'),
('2410110318', 'SHAURYA AJIT SINGH', 'shaurya.singh@snu.edu.in', 'hashed_pass_singh318'),
('2410110321', 'SHIVEN  AGARWAL', 'shiven@snu.edu.in', 'hashed_pass_agarwal321'),
('2410110323', 'SHREE  GATTANI', 'shree@snu.edu.in', 'hashed_pass_gattani323'),
('2410110346', 'SUNAINA  GOEL', 'sunaina@snu.edu.in', 'hashed_pass_goel346'),
('2410110348', 'SURYA  K', 'surya@snu.edu.in', 'hashed_pass_k348'),
('2410110353', 'TALISH  KUNDRA', 'talish@snu.edu.in', 'hashed_pass_kundra353'),
('2410110354', 'TANISHA  AGRAWAL', 'tanisha@snu.edu.in', 'hashed_pass_agrawal354'),
('2410110356', 'TANVI  PANDEY', 'tanvi@snu.edu.in', 'hashed_pass_pandey356'),
('2410110360', 'THRIAMBAKESH  S P', 'thriambakesh@snu.edu.in', 'hashed_pass_p360'),
('2410110361', 'TILIKA  CHOPRA', 'tilika@snu.edu.in', 'hashed_pass_chopra361'),
('2410110362', 'TRISHAY  KAUL', 'trishay@snu.edu.in', 'hashed_pass_kaul362'),
('2410110363', 'TUSHAR  PANDEY', 'tushar@snu.edu.in', 'hashed_pass_pandey363'),
('2410110366', 'VAIDEHI  SAXENA', 'vaidehi@snu.edu.in', 'hashed_pass_saxena366'),
('2410110367', 'VANSH  GARG', 'vansh@snu.edu.in', 'hashed_pass_garg367'),
('2410110374', 'VEDAANT  WALIA', 'vedaant@snu.edu.in', 'hashed_pass_walia374'),
('2410110376', 'VELAGALA SURYA  PRAKASH REDDY', 'velagala@snu.edu.in', 'hashed_pass_reddy376'),
('2410110385', 'YASHVARDHAN SINGH CHAUHAN', 'yashvardhan@snu.edu.in', 'hashed_pass_chauhan385'),
('2410110388', 'AADARSH  KUMAR', 'aadarsh@snu.edu.in', 'hashed_pass_kumar388'),
('2410110391', 'AARUSH MOHAN MATHUR', 'aarush@snu.edu.in', 'hashed_pass_mathur391'),
('2410110392', 'AARYAMAN  RANA', 'aaryaman@snu.edu.in', 'hashed_pass_rana392'),
('2410110398', 'ADITYA  VERMA', 'aditya@snu.edu.in', 'hashed_pass_verma398'),
('2410110404', 'ANTRA  AGARWAL', 'antra@snu.edu.in', 'hashed_pass_agarwal404'),
('2410110406', 'ARJUN  KAPOOR', 'arjun@snu.edu.in', 'hashed_pass_kapoor406'),
('2410110408', 'ARTH PRATAP SINGH TOMAR', 'arth@snu.edu.in', 'hashed_pass_tomar408'),
('2410110417', 'BUDHARAPU DAKSHAYANI SAI', 'budharapu@snu.edu.in', 'hashed_pass_sai417'),
('2410110420', 'DIVYA MANI  TRIPATHI', 'divya@snu.edu.in', 'hashed_pass_tripathi420'),
('2410110422', 'FARHAN  NAIK', 'farhan@snu.edu.in', 'hashed_pass_naik422'),
('2410110426', 'HARSITH  N V', 'harsith@snu.edu.in', 'hashed_pass_v426'),
('2410110427', 'HUNAR  BHATIA', 'hunar@snu.edu.in', 'hashed_pass_bhatia427'),
('2410110429', 'ISHAAN  PRAKASH', 'ishaan@snu.edu.in', 'hashed_pass_prakash429');

-- Pre-populate Default Attendance rows for all students
INSERT INTO attendance (exam_id, student_id, status) VALUES
(1, 1, 'ABSENT'), (1, 2, 'ABSENT'), (1, 3, 'ABSENT'), (1, 4, 'ABSENT'), (1, 5, 'ABSENT'),
(1, 6, 'ABSENT'), (1, 7, 'ABSENT'), (1, 8, 'ABSENT'), (1, 9, 'ABSENT'), (1, 10, 'ABSENT'),
(1, 11, 'ABSENT'), (1, 12, 'ABSENT'), (1, 13, 'ABSENT'), (1, 14, 'ABSENT'), (1, 15, 'ABSENT'),
(1, 16, 'ABSENT'), (1, 17, 'ABSENT'), (1, 18, 'ABSENT'), (1, 19, 'ABSENT'), (1, 20, 'ABSENT'),
(1, 21, 'ABSENT'), (1, 22, 'ABSENT'), (1, 23, 'ABSENT'), (1, 24, 'ABSENT'), (1, 25, 'ABSENT'),
(1, 26, 'ABSENT'), (1, 27, 'ABSENT'), (1, 28, 'ABSENT'), (1, 29, 'ABSENT'), (1, 30, 'ABSENT'),
(1, 31, 'ABSENT'), (1, 32, 'ABSENT'), (1, 33, 'ABSENT'), (1, 34, 'ABSENT'), (1, 35, 'ABSENT'),
(1, 36, 'ABSENT'), (1, 37, 'ABSENT'),
(2, 1, 'ABSENT'), (2, 2, 'ABSENT'), (2, 3, 'ABSENT'), (2, 4, 'ABSENT'), (2, 5, 'ABSENT'),
(2, 6, 'ABSENT'), (2, 7, 'ABSENT'), (2, 8, 'ABSENT'), (2, 9, 'ABSENT'), (2, 10, 'ABSENT'),
(2, 11, 'ABSENT'), (2, 12, 'ABSENT'), (2, 13, 'ABSENT'), (2, 14, 'ABSENT'), (2, 15, 'ABSENT'),
(2, 16, 'ABSENT'), (2, 17, 'ABSENT'), (2, 18, 'ABSENT'), (2, 19, 'ABSENT'), (2, 20, 'ABSENT'),
(2, 21, 'ABSENT'), (2, 22, 'ABSENT'), (2, 23, 'ABSENT'), (2, 24, 'ABSENT'), (2, 25, 'ABSENT'),
(2, 26, 'ABSENT'), (2, 27, 'ABSENT'), (2, 28, 'ABSENT'), (2, 29, 'ABSENT'), (2, 30, 'ABSENT'),
(2, 31, 'ABSENT'), (2, 32, 'ABSENT'), (2, 33, 'ABSENT'), (2, 34, 'ABSENT'), (2, 35, 'ABSENT'),
(2, 36, 'ABSENT'), (2, 37, 'ABSENT');

-- Example execution of marking attendance using the Store Procedure
-- (We will let the Python app execute this later)
-- CALL MarkAttendance('some_hash', 1, 1, @out_msg, @out_name, @out_enroll);
