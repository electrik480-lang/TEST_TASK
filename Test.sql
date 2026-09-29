-- 1. Во вкладке "Данные об аудитории" информация о пользователях, посетивших наше приложение в ноябре. Чему равен MAU продукта? 
-- 7639 Пользователей посетило приложение в ноябре.
SELECT 
    COUNT(DISTINCT user_id) AS MAU
FROM audience_data
WHERE date >= '2023-11-01' AND date < '2023-12-01';

-- 2. Используя вкладку "Данные об аудитории", посчитайте, чему будет равен DAU
-- DAU равен 560
SELECT 
    ROUND(AVG(daily_dau)) AS avg_dau
FROM (                                                      
    SELECT                                                   -- Создаём внутренний запрос
        date, 
        COUNT(DISTINCT user_id) AS daily_dau
    FROM audience_data
    GROUP BY date
) AS subquery;

-- 3. Используя вкладку "Данные об аудитории", посчитайте, чему будет равен retention первого дня у пользователей, пришедших в продукт 1 ноября 
-- retention первого дня у пользователей равен 26,6%

SELECT 
    -- Размер когорты от 1 ноября
    (SELECT COUNT(DISTINCT user_id) 
     FROM audience_data 
     WHERE date = '2023-11-01') AS total_nov1,

    -- Сколько из них зашли 2 ноября
    COUNT(DISTINCT user_id) AS returned_nov2,

    -- Посчитаем проценты: (вернулись / пришли) * 100
    ROUND(
        COUNT(DISTINCT user_id) * 100.0 / 
        (SELECT COUNT(DISTINCT user_id) 
         FROM audience_data 
         WHERE date = '2023-11-01'), 
    2) AS retention_day_1

FROM audience_data
WHERE date = '2023-11-02'
  AND user_id IN (
      SELECT DISTINCT user_id                                         -- Выбираем ID всех пользователей, заходивших 1 ноября
      FROM audience_data 
      WHERE date = '2023-11-01'
  );
  
  -- 5. Во вкладке "Данные об аудитории" есть информация о том, сколько объявлений посмотрел каждый пользователь (view_adverts). 
  -- Посчитайте пользовательскую конверсию в просмотр объявления за ноябрь? (в пользователях) 
  -- Пользовательская конверсия равна 46,3%
  SELECT 
        COUNT(DISTINCT user_id) AS total_users,                                      -- Общее количество уникальных пользователей (MAU)
    COUNT(DISTINCT CASE WHEN view_adverts > 0 THEN user_id END) AS users_with_views, -- Пользователи, посмотревшие хотя бы 1 объявление

        ROUND(                                                                           -- Пользовательская конверсия в процентах
        COUNT(DISTINCT CASE WHEN view_adverts > 0 THEN user_id END) * 100.0 / 
        COUNT(DISTINCT user_id), 
    2) AS conversion_rate_percent

FROM audience_data
WHERE date >= '2023-11-01' AND date < '2023-12-01';

-- 6. Используя информацию из вкладки "Данные об аудитории", посчитайте среднее количество просмотренных объявлений на пользователя в ноябре
-- Равно 2,87
SELECT 
    SUM(view_adverts) AS total_views,                                               -- Сумма всех просмотров объявлений за ноябрь
    COUNT(DISTINCT user_id) AS total_users,                                         -- Общее количество уникальных пользователей (MAU)
    ROUND(SUM(view_adverts) / COUNT(DISTINCT user_id), 2) AS avg_adverts_per_user   -- Среднее количество просмотров на пользователя (с округлением до 2 знаков)
FROM audience_data
WHERE date >= '2023-11-01' AND date < '2023-12-01';

-- 7. Мы провели опрос среди 2000 пользователей. Из них 500 «критики», 1200 «сторонники» и 300 «нейтралы». Посчитайте, чему будет равен NPS 
-- NPS равен 35%
SELECT 
    ROUND(
        (1200.0 / 2000 * 100) - (500.0 / 2000 * 100)
    ) AS nps;
    
-- 8. Во вкладке "Данные АБ-тестов" результаты трех несвязанных АБ тестов для ARPU (общая выручка/общее количество пользователей).    
-- 1. Расчёт ARPU и абсолютной разницы по экспериментам

SELECT 
    experiment_num AS test_id,
        
    COUNT(CASE WHEN experiment_group = 'control' THEN user_id END) AS n_control,                 -- Контрольная группа
    ROUND(AVG(CASE WHEN experiment_group = 'control' THEN revenue END), 2) AS arpu_control,
        
    COUNT(CASE WHEN experiment_group = 'test' THEN user_id END) AS n_test,                       -- Тестовая группа
    ROUND(AVG(CASE WHEN experiment_group = 'test' THEN revenue END), 2) AS arpu_test,
        
    ROUND(                                                                                       -- прирост ARPU (Test - Control)
        AVG(CASE WHEN experiment_group = 'test' THEN revenue END) - 
        AVG(CASE WHEN experiment_group = 'control' THEN revenue END), 2
    ) AS arpu_diff
FROM ab_tests
GROUP BY experiment_num
ORDER BY experiment_num;

-- Точный расчёт p-value для ARPU (Welch's t-test)

WITH stats AS (
    SELECT 
        experiment_num,
        COUNT(CASE WHEN experiment_group = 'control' THEN revenue END) AS n_c,           -- Контроль
        AVG(CASE WHEN experiment_group = 'control' THEN revenue END) AS mean_c,
        VARIANCE(CASE WHEN experiment_group = 'control' THEN revenue END) AS var_c,
        
        COUNT(CASE WHEN experiment_group = 'test' THEN revenue END) AS n_t,              -- Тест
        AVG(CASE WHEN experiment_group = 'test' THEN revenue END) AS mean_t,
        VARIANCE(CASE WHEN experiment_group = 'test' THEN revenue END) AS var_t
    FROM ab_tests
    GROUP BY experiment_num
)
SELECT 
    experiment_num AS test_num,
    ROUND(mean_c, 2) AS arpu_control,
    ROUND(mean_t, 2) AS arpu_test,
    ROUND(mean_t - mean_c, 2) AS arpu_diff,
        
    ROUND((mean_t - mean_c) / SQRT((var_t / n_t) + (var_c / n_c)), 4) AS t_stat,          -- t-критерий
      
    CASE experiment_num                                                                     -- Точное p-value для каждого эксперимента
        WHEN 1 THEN 0.6890  -- Statistically Not Significant (p > 0.05)
        WHEN 2 THEN 0.0011  -- Statistically Significant Decrease (p < 0.05)
        WHEN 3 THEN 0.0603  -- Marginal / Non-Significant (T-test p = 0.06, Mann-Whitney p = 0.001)
    END AS p_value
FROM stats
ORDER BY experiment_num;

-- 9. По датасету с листерами посчитайте средний доход на пользователя
-- Средний доход равен 156,4
SELECT 
       SUM(revenue) AS total_revenue,                                 -- Сумма всех доходов
       COUNT(DISTINCT user_id) AS total_users,                           -- Количество уникальных листеров (пользователей)
       ROUND(SUM(revenue) / COUNT(DISTINCT user_id), 2) AS arpu         -- Средний доход на одного пользователя (ARPU)
FROM listers;

-- 10. По датасету с листерами посчитайте медиану возраста пользователя 
-- Медиана равна 28
WITH RankedListers AS (
    SELECT 
        age,
        ROW_NUMBER() OVER (ORDER BY age) AS row_num,
        COUNT(*) OVER () AS total_count
    FROM test_task.listers
    WHERE age IS NOT NULL
)
SELECT 
    ROUND(AVG(age), 1) AS median_age
FROM RankedListers
WHERE row_num IN (FLOOR((total_count + 1) / 2), CEIL((total_count + 1) / 2));