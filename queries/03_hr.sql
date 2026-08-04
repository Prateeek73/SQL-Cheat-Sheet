-- Q1: Salary statistics by department ==> Beginner-friendly
SELECT
    department, COUNT(*) AS headcount, ROUND(AVG(salary), 2) AS avg_salary,
    MIN(salary) AS min_salary, MAX(salary) AS max_salary,
    ROUND(sqrt( (SUM(salary * salary) - SUM(salary) * SUM(salary) / COUNT(*))
                / NULLIF(COUNT(*) - 1, 0) ), 2) AS salary_stddev
FROM employees
GROUP BY department
ORDER BY avg_salary DESC;

-- Q2: Headcount and performance coverage by department ==> Beginner-friendly
SELECT
    e.department, COUNT(*) AS employees, COUNT(p.performance_score) AS with_score,
    COUNT(*) - COUNT(p.performance_score) AS missing_score,
    ROUND(100.0 * COUNT(p.performance_score) / COUNT(*), 1) AS score_coverage_pct,
    ROUND(AVG(p.performance_score), 2) AS avg_score_where_known
FROM employees e
LEFT JOIN performance p ON e.employee_id = p.employee_id
GROUP BY e.department
ORDER BY e.department;

-- Q3: Most recent hires ==> Beginner-friendly
SELECT
    employee_id, employee_name, department, location, joining_date, salary, experience_years,
    CAST(julianday((SELECT MAX(joining_date) FROM employees))
         - julianday(joining_date) AS INTEGER) AS days_before_latest_hire
FROM employees
WHERE joining_date >= date((SELECT MAX(joining_date) FROM employees), '-12 months')
ORDER BY joining_date DESC;

-- Q4: Salary by location and shift session ==> Beginner-friendly
SELECT
    location, session, COUNT(*) AS headcount, ROUND(AVG(salary), 2) AS avg_salary,
    MIN(salary) AS min_salary, MAX(salary) AS max_salary,
    MAX(salary) - MIN(salary) AS salary_spread
FROM employees
GROUP BY location, session
HAVING COUNT(*) >= 3
ORDER BY avg_salary DESC;

-- Q5: Active vs inactive workforce ==> Beginner-friendly
SELECT
    department, COUNT(*) AS total,
    SUM(CASE WHEN status = 'Active' THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN status = 'Inactive' THEN 1 ELSE 0 END) AS inactive,
    ROUND(100.0 * SUM(CASE WHEN status = 'Inactive' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_rate_pct,
    ROUND(AVG(CASE WHEN status = 'Inactive' THEN salary END), 2) AS avg_salary_leavers,
    ROUND(AVG(CASE WHEN status = 'Active' THEN salary END), 2) AS avg_salary_stayers
FROM employees
GROUP BY department
ORDER BY attrition_rate_pct DESC;

-- Q6: Age distribution ==> Beginner-friendly
SELECT
    CASE
        WHEN age < 30 THEN '20-29'
        WHEN age < 40 THEN '30-39'
        WHEN age < 50 THEN '40-49'
        WHEN age < 60 THEN '50-59'
        ELSE '60+'
    END AS age_band,
    COUNT(*) AS employees, ROUND(AVG(salary), 2) AS avg_salary,
    ROUND(AVG(experience_years), 1) AS avg_experience
FROM employees
GROUP BY age_band
ORDER BY MIN(age);

-- Q7: Salary rank within department ==> Intermediate-friendly
SELECT
    employee_id, employee_name, department, salary,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS salary_rank,
    ROUND(AVG(salary) OVER (PARTITION BY department), 2) AS dept_avg,
    ROUND(salary - AVG(salary) OVER (PARTITION BY department), 2) AS vs_dept_avg,
    ROUND(100.0 * salary / SUM(salary) OVER (PARTITION BY department), 3) AS pct_of_dept_payroll
FROM employees
ORDER BY department, salary_rank;

-- Q8: Top 3 performers per department ==> Intermediate-friendly
WITH ranked AS (
    SELECT
        e.employee_id, e.employee_name, e.department, e.salary,
        p.performance_score,
        ROW_NUMBER() OVER (PARTITION BY e.department
                           ORDER BY p.performance_score DESC, e.salary DESC) AS rn
    FROM employees e
    INNER JOIN performance p ON e.employee_id = p.employee_id
)
SELECT department, rn AS rank_in_dept, employee_id, employee_name,
       performance_score, salary
FROM ranked
WHERE rn <= 3
ORDER BY department, rn;

-- Q9: Salary percentiles and quartiles ==> Intermediate-friendly
SELECT
    employee_id, employee_name, department, salary,
    ROUND(100 * PERCENT_RANK() OVER (ORDER BY salary), 2) AS salary_percentile,
    NTILE(4) OVER (ORDER BY salary) AS quartile,
    CASE NTILE(4) OVER (ORDER BY salary)
        WHEN 4 THEN 'Top 25%'
        WHEN 3 THEN 'Upper mid'
        WHEN 2 THEN 'Lower mid'
        ELSE 'Bottom 25%'
    END AS pay_band
FROM employees
ORDER BY salary DESC
LIMIT 100;

-- Q10: Tenure derived from joining_date ==> Intermediate-friendly
SELECT
    employee_id, employee_name, department, joining_date, experience_years,
    CAST(julianday((SELECT MAX(joining_date) FROM employees))
         - julianday(joining_date) AS INTEGER) AS tenure_days,
    (CAST(strftime('%Y', (SELECT MAX(joining_date) FROM employees)) AS INTEGER)
       - CAST(strftime('%Y', joining_date) AS INTEGER)) * 12
    + (CAST(strftime('%m', (SELECT MAX(joining_date) FROM employees)) AS INTEGER)
       - CAST(strftime('%m', joining_date) AS INTEGER)) AS tenure_months,
    ROUND((julianday((SELECT MAX(joining_date) FROM employees))
           - julianday(joining_date)) / 365.25, 1) AS tenure_years
FROM employees
ORDER BY tenure_days DESC
LIMIT 100;

-- Q11: Does experience translate into pay? ==> Intermediate-friendly
WITH bands AS (
    SELECT
        CASE
            WHEN experience_years < 3 THEN '0-2 yrs'
            WHEN experience_years < 6 THEN '3-5 yrs'
            WHEN experience_years < 11 THEN '6-10 yrs'
            WHEN experience_years < 16 THEN '11-15 yrs'
            ELSE '16+ yrs'
        END AS experience_band,
        MIN(experience_years) AS band_floor, COUNT(*) AS employees,
        ROUND(AVG(salary), 2) AS avg_salary
    FROM employees
    GROUP BY experience_band
)
SELECT
    experience_band, employees, avg_salary,
    ROUND(avg_salary - LAG(avg_salary) OVER (ORDER BY band_floor), 2) AS step_up_vs_prev_band,
    ROUND(100.0 * (avg_salary - FIRST_VALUE(avg_salary) OVER (ORDER BY band_floor))
          / FIRST_VALUE(avg_salary) OVER (ORDER BY band_floor), 1) AS pct_above_entry_band
FROM bands
ORDER BY band_floor;

-- Q12: Salary outliers within department (z-score) ==> Intermediate-friendly
WITH stats AS (
    SELECT department,
           AVG(salary) AS mean_salary,
           sqrt( (SUM(salary * salary) - SUM(salary) * SUM(salary) / COUNT(*))
                 / NULLIF(COUNT(*) - 1, 0) ) AS sd_salary
    FROM employees
    GROUP BY department
)
SELECT
    e.employee_id, e.employee_name, e.department, e.salary,
    ROUND(s.mean_salary, 2) AS dept_mean, ROUND(s.sd_salary, 2) AS dept_sd,
    ROUND((e.salary - s.mean_salary) / NULLIF(s.sd_salary, 0), 2) AS z_score,
    CASE
        WHEN (e.salary - s.mean_salary) / NULLIF(s.sd_salary, 0) > 1.5 THEN 'Paid well above peers'
        WHEN (e.salary - s.mean_salary) / NULLIF(s.sd_salary, 0) < -1.5 THEN 'Paid well below peers'
        ELSE 'Within normal range'
    END AS assessment
FROM employees e
JOIN stats s ON e.department = s.department
WHERE ABS((e.salary - s.mean_salary) / NULLIF(s.sd_salary, 0)) > 1.5
ORDER BY ABS((e.salary - s.mean_salary) / NULLIF(s.sd_salary, 0)) DESC;

-- Q13: Attrition by tenure and department ==> Intermediate-friendly
WITH tenure AS (
    SELECT
        department, status, salary,
        CASE
            WHEN experience_years < 2 THEN '0-1 yrs'
            WHEN experience_years < 5 THEN '2-4 yrs'
            WHEN experience_years < 10 THEN '5-9 yrs'
            ELSE '10+ yrs'
        END AS tenure_band,
        MIN(experience_years) OVER () AS dummy
    FROM employees
)
SELECT
    tenure_band, department, COUNT(*) AS employees,
    SUM(CASE WHEN status = 'Inactive' THEN 1 ELSE 0 END) AS left_company,
    ROUND(100.0 * SUM(CASE WHEN status = 'Inactive' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_pct,
    ROUND(AVG(salary), 2) AS avg_salary
FROM tenure
GROUP BY tenure_band, department
HAVING COUNT(*) >= 10
ORDER BY attrition_pct DESC;

-- Q14: Is pay aligned with performance? ==> Intermediate-friendly
SELECT
    COALESCE(CAST(p.performance_score AS TEXT), 'No score on file') AS performance_score,
    COUNT(*) AS employees, ROUND(AVG(e.salary), 2) AS avg_salary, MIN(e.salary) AS min_salary,
    MAX(e.salary) AS max_salary,
    ROUND(AVG(e.experience_years), 1) AS avg_experience,
    ROUND(100.0 * SUM(CASE WHEN e.status = 'Inactive' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_pct
FROM employees e
LEFT JOIN performance p ON e.employee_id = p.employee_id
GROUP BY p.performance_score
ORDER BY (p.performance_score IS NULL), p.performance_score;

-- Q15: Pay equity by gender within department ==> Advanced-friendly
WITH cell AS (
    SELECT department, gender,
           COUNT(*) AS employees, ROUND(AVG(salary), 2) AS avg_salary,
           ROUND(AVG(experience_years), 1) AS avg_experience
    FROM employees
    GROUP BY department, gender
),
dept_base AS (
    SELECT department,
           ROUND(AVG(salary), 2) AS dept_avg_salary,
           COUNT(*) AS dept_headcount
    FROM employees GROUP BY department
)
SELECT
    c.department, c.gender, c.employees, c.avg_salary, c.avg_experience, d.dept_avg_salary,
    ROUND(c.avg_salary - d.dept_avg_salary, 2) AS gap_vs_dept_avg,
    ROUND(100.0 * (c.avg_salary - d.dept_avg_salary) / d.dept_avg_salary, 2) AS gap_pct,
    ROUND(100.0 * c.employees / d.dept_headcount, 1) AS share_of_dept_pct,
    CASE
        WHEN ABS(100.0 * (c.avg_salary - d.dept_avg_salary) / d.dept_avg_salary) < 2 THEN 'At parity'
        WHEN c.avg_salary > d.dept_avg_salary THEN 'Above dept average'
        ELSE 'Below dept average'
    END AS equity_flag
FROM cell c
JOIN dept_base d ON c.department = d.department
WHERE c.employees >= 20
ORDER BY c.department, c.avg_salary DESC;

-- Q16: Compensation bands from real percentiles ==> Advanced-friendly
WITH ranked AS (
    SELECT department, salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary) AS rn,
           COUNT(*) OVER (PARTITION BY department) AS n
    FROM employees
)
SELECT
    department, n AS headcount,
    MAX(CASE WHEN rn = 1 THEN salary END) AS min_salary,
    MAX(CASE WHEN rn = CAST(0.25*(n-1)+1 AS INTEGER) THEN salary END) AS p25,
    MAX(CASE WHEN rn = CAST(0.50*(n-1)+1 AS INTEGER) THEN salary END) AS median,
    MAX(CASE WHEN rn = CAST(0.75*(n-1)+1 AS INTEGER) THEN salary END) AS p75,
    MAX(CASE WHEN rn = CAST(0.90*(n-1)+1 AS INTEGER) THEN salary END) AS p90,
    MAX(CASE WHEN rn = n THEN salary END) AS max_salary,
    MAX(CASE WHEN rn = CAST(0.75*(n-1)+1 AS INTEGER) THEN salary END)
      - MAX(CASE WHEN rn = CAST(0.25*(n-1)+1 AS INTEGER) THEN salary END) AS iqr
FROM ranked
GROUP BY department, n
ORDER BY median DESC;

-- Q17: Is the missing performance data random? ==> Advanced-friendly
WITH flagged AS (
    SELECT e.*,
           CASE WHEN p.employee_id IS NULL THEN 'Missing score' ELSE 'Has score' END AS score_status
    FROM employees e
    LEFT JOIN performance p ON e.employee_id = p.employee_id
)
SELECT
    score_status, COUNT(*) AS employees,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM employees), 1) AS pct_of_workforce,
    ROUND(AVG(salary), 2) AS avg_salary, ROUND(AVG(age), 1) AS avg_age,
    ROUND(AVG(experience_years), 1) AS avg_experience,
    ROUND(100.0 * SUM(CASE WHEN status = 'Inactive' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_pct,
    ROUND(100.0 * SUM(CASE WHEN department = 'IT' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_it,
    ROUND(100.0 * SUM(CASE WHEN department = 'Sales' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_sales,
    ROUND(100.0 * SUM(CASE WHEN department = 'HR' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_hr
FROM flagged
GROUP BY score_status;

-- Q18: Attrition risk score ==> Advanced-friendly
WITH dept_stats AS (
    SELECT department, AVG(salary) AS dept_avg FROM employees GROUP BY department
),
scored AS (
    SELECT
        e.employee_id, e.employee_name, e.department, e.salary,
        e.experience_years, e.age, p.performance_score, d.dept_avg,
        (CASE WHEN e.experience_years BETWEEN 2 AND 4 THEN 25 ELSE 0 END) +
        (CASE WHEN e.salary < d.dept_avg * 0.85 THEN 25 ELSE 0 END) +
        (CASE WHEN p.performance_score >= 4 THEN 20 ELSE 0 END) +
        (CASE WHEN p.performance_score <= 2 THEN 15 ELSE 0 END) +
        (CASE WHEN p.performance_score IS NULL THEN 10 ELSE 0 END) +
        (CASE WHEN e.age < 30 THEN 10 ELSE 0 END) AS raw_score
    FROM employees e
    JOIN dept_stats d ON e.department = d.department
    LEFT JOIN performance p ON e.employee_id = p.employee_id
    WHERE e.status = 'Active'
)
SELECT
    employee_id, employee_name, department, salary,
    ROUND(dept_avg, 2) AS dept_avg_salary, experience_years, performance_score,
    MIN(raw_score, 100) AS attrition_risk_score,
    CASE
        WHEN raw_score >= 60 THEN 'Critical'
        WHEN raw_score >= 40 THEN 'High'
        WHEN raw_score >= 20 THEN 'Medium'
        ELSE 'Low'
    END AS risk_tier,
    CASE
        WHEN salary < dept_avg * 0.85 AND performance_score >= 4
             THEN 'Underpaid high performer - salary review'
        WHEN performance_score >= 4
             THEN 'High performer - development conversation'
        WHEN performance_score <= 2
             THEN 'Performance support plan'
        WHEN performance_score IS NULL
             THEN 'No review on file - schedule one'
        ELSE 'Standard management'
    END AS recommended_action
FROM scored
WHERE raw_score >= 20
ORDER BY raw_score DESC, salary
LIMIT 200;

-- Q19: Department balanced scorecard ==> Advanced-friendly
WITH metrics AS (
    SELECT
        e.department, COUNT(*) AS headcount, ROUND(AVG(e.salary), 2) AS avg_salary,
        ROUND(AVG(p.performance_score), 2) AS avg_performance,
        ROUND(AVG(e.experience_years), 1) AS avg_experience,
        ROUND(100.0 * SUM(CASE WHEN e.status = 'Inactive' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_pct,
        ROUND(100.0 * COUNT(p.performance_score) / COUNT(*), 1) AS review_coverage_pct
    FROM employees e
    LEFT JOIN performance p ON e.employee_id = p.employee_id
    GROUP BY e.department
),
scored AS (
    SELECT *,
        ROUND(100.0 * avg_performance / 5.0, 1) AS performance_index,
        ROUND(100.0 - attrition_pct, 1) AS retention_index,
        ROUND(review_coverage_pct, 1) AS governance_index
    FROM metrics
)
SELECT
    department, headcount, avg_salary, avg_performance, avg_experience,
    attrition_pct, review_coverage_pct,
    performance_index, retention_index, governance_index,
    ROUND((performance_index + retention_index + governance_index) / 3.0, 1) AS overall_score,
    RANK() OVER (ORDER BY (performance_index + retention_index + governance_index) DESC) AS dept_rank
FROM scored
ORDER BY overall_score DESC;

-- Q20: Five-year salary projection ==> Advanced-friendly
WITH rates AS (
    SELECT
        e.employee_id, e.employee_name, e.department, e.salary,
        p.performance_score,
        CASE
            WHEN p.performance_score >= 4.5 THEN 0.06
            WHEN p.performance_score >= 4.0 THEN 0.05
            WHEN p.performance_score >= 3.0 THEN 0.04
            WHEN p.performance_score IS NOT NULL THEN 0.025
            ELSE 0.03 -- no score on file: company default
        END AS annual_growth_rate
    FROM employees e
    LEFT JOIN performance p ON e.employee_id = p.employee_id
    WHERE e.status = 'Active'
),
projected AS (
    SELECT *,
        ROUND(salary * POWER(1 + annual_growth_rate, 1), 2) AS year_1,
        ROUND(salary * POWER(1 + annual_growth_rate, 3), 2) AS year_3,
        ROUND(salary * POWER(1 + annual_growth_rate, 5), 2) AS year_5
    FROM rates
)
SELECT
    employee_id, employee_name, department,
    COALESCE(CAST(performance_score AS TEXT), 'none') AS performance_score,
    salary AS current_salary,
    ROUND(100.0 * annual_growth_rate, 1) AS growth_rate_pct,
    year_1, year_3, year_5,
    ROUND(year_5 - salary, 2) AS total_increase_5yr,
    ROUND(100.0 * (year_5 - salary) / salary, 1) AS pct_increase_5yr,
    SUM(year_5 - salary) OVER (PARTITION BY department) AS dept_incremental_cost_5yr
FROM projected
ORDER BY total_increase_5yr DESC
LIMIT 200;

-- Q21: Employees against the department dimension ==> Extended-friendly
SELECT
    d.department_name, d.headcount AS dim_headcount, d.avg_salary AS dim_avg_salary,
    COUNT(e.employee_id) AS live_headcount, ROUND(AVG(e.salary), 2) AS live_avg_salary,
    ROUND(d.avg_salary - AVG(e.salary), 6) AS cache_drift,
    COUNT(p.performance_score) AS with_score,
    ROUND(AVG(p.performance_score), 2) AS avg_score,
    SUM(CASE WHEN e.salary > d.avg_salary THEN 1 ELSE 0 END) AS paid_above_dept_avg,
    ROUND(100.0 * SUM(CASE WHEN e.salary > d.avg_salary THEN 1 ELSE 0 END)
          / COUNT(e.employee_id), 1) AS pct_above_dept_avg
FROM departments d
JOIN employees e ON e.department = d.department_name
LEFT JOIN performance p ON p.employee_id = e.employee_id
GROUP BY d.department_name, d.headcount, d.avg_salary
ORDER BY d.avg_salary DESC;
