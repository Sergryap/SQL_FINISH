--1. В каких городах больше одного аэропорта?
SELECT city, count(*) "Кол-во аэропортов"
FROM bookings.airports a 
GROUP BY city -- делаем группировку по городам
HAVING count(*) >1; -- если строк в группе более 1, значит там более 1 аэропорта

--2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?  
SELECT DISTINCT airport_code, (
	SELECT max("range")
	FROM bookings.aircrafts) Дальность
FROM bookings.airports
JOIN bookings.flights
ON departure_airport = airport_code OR arrival_airport = airport_code
WHERE aircraft_code = ( 
	SELECT aircraft_code -- находим код самолета с максимальной дальностью
	FROM bookings.aircrafts
	WHERE "range" = (
	SELECT max("range") -- находим максимальную дальность
	FROM bookings.aircrafts));
  
--3. Вывести 10 рейсов с максимальным временем задержки вылета
SELECT flight_id, flight_no, actual_departure - scheduled_departure "Задержка"
FROM bookings.flights
WHERE actual_departure IS NOT NULL -- исключаем рейсы без задержек
ORDER BY actual_departure - scheduled_departure DESC 
LIMIT 10;

--4. Были ли брони, по которым не были получены посадочные талоны
SELECT ticket_no
FROM bookings.ticket_flights	
	LEFT JOIN boarding_passes USING (ticket_no) --объединяем с влючением значений NULL из правой таблицы
WHERE boarding_no IS NULL --отбираем те билеты, по которым не было брони
ORDER BY ticket_no;


/*
5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день.
Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах в течении дня.*/

/*В первом cte находим общее количество мест для каждого рейса
по общему количеству мест в самолете, забронированному на данный рейс*/
with seats_flats_cte as (
select flight_id, count(*) count_seats, departure_airport, scheduled_departure, actual_departure,
case
	when actual_departure is null then scheduled_departure
	else actual_departure
end fact_departure --фактическое время вылета
from
	bookings.flights f	
	join bookings.seats s  using (aircraft_code)
group by flight_id , aircraft_code -- группируем для подсчета количества мест в самолете по рейсам
order by flight_id),
--Находим количество посадочных талонов для каждого рейса
count_boarding_passes_cte as (
select flight_id, count(*) count_passes
from bookings.boarding_passes bp 
group by flight_id
order by flight_id),
--Находим количество свободных мест для каждого рейса
free_seats_flats_cte as (
select *
from
	seats_flats_cte --Объединяем через left join, чтобы учесть null
	left join count_boarding_passes_cte using (flight_id))
select flight_id, fact_departure,
case
	when count_passes is null then count_seats
	else count_seats - count_passes
end free_seats,
case
	when count_passes is null then 100
	else round(((count_seats - count_passes)::numeric/count_seats)*100, 1)
end "free_seats, %",
coalesce(sum(count_passes) over(partition by departure_airport, fact_departure::date order by fact_departure), 0) "count_sum"
from free_seats_flats_cte
order by departure_airport, fact_departure;

--6. Найдите процентное соотношение перелетов по типам самолетов от общего количества.
select distinct 
	aircraft_code,
	round((count(aircraft_code) over(partition by aircraft_code))::numeric / (
	select count(*) from bookings.flights), 3)*100 "Доля, %"
from
	bookings.flights;
	
/*
7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета? */
	
	
--Вариант 1
--Для начала находим стоимость перелетов по рейсам и классам
with amount_city_cte as (
select distinct 
	flight_id, amount, fare_conditions
from
	bookings.ticket_flights tf
	join bookings.flights using(flight_id)
	join bookings.aircrafts using(aircraft_code)),
-- отбираем перелеты по классу Economy
amount_city_cte_economy as (
select *
from amount_city_cte
where fare_conditions = 'Economy'),
-- отбираем перелеты по классу Business
amount_city_cte_business as (
select *
from amount_city_cte
where fare_conditions = 'Business')
-- соединяем cte перелетов по разным классам по условию равенства flight_id
select
	flight_id
from
	amount_city_cte_economy
	join amount_city_cte_business using(flight_id)
where amount_city_cte_business.amount < amount_city_cte_economy.amount; -- отбираем по этому условию 
--Результат нулевой. Значит не было
								  

--Вариант 2
--Для начала находим максимальные и минимальные стоимость перелетов по рейсам и классам для Economy и Business
--С группировкой по flight_id, fare_conditions

with amount_city_cte as (
SELECT 
	flight_id, fare_conditions,
	CASE 
		WHEN fare_conditions = 'Economy' THEN max(amount)
		ELSE min(amount)
	END amount
from
	bookings.ticket_flights tf
	join bookings.flights using(flight_id)
	join bookings.aircrafts using(aircraft_code)
WHERE tf.fare_conditions = 'Business' OR tf.fare_conditions = 'Economy'
GROUP BY flight_id, fare_conditions
ORDER BY flight_id, fare_conditions
	)
	SELECT flight_id
	from
		(SELECT flight_id, array_agg(fare_conditions) fare_conditions, array_agg(amount) amount 
		FROM amount_city_cte
		GROUP BY flight_id
		HAVING count(*) > 1) q
	WHERE amount[1] < amount[2];  --проверяем значения в массиве
--Результат нулевой. Значит не было
	
	
--Вариант 3
--Для начала находим максимальные и минимальные стоимость перелетов по рейсам и классам для Economy и Business
--С группировкой по flight_id, fare_conditions
with amount_city_cte as (
SELECT 
	flight_id, fare_conditions,
	CASE --для Economy берем максимальную стоимость для рейса
		WHEN fare_conditions = 'Economy' THEN max(amount)
		ELSE min(amount) --для Business берем минимальную стоимость для рейса
	END amount
from
	bookings.ticket_flights tf
	join bookings.flights using(flight_id)	
	join bookings.aircrafts using(aircraft_code)
WHERE fare_conditions = 'Business' OR fare_conditions = 'Economy'
GROUP BY flight_id, fare_conditions
ORDER BY flight_id, fare_conditions
	)
SELECT flight_id
FROM (
		SELECT *,
	 --добавляем колонку значений минимальной стоимости бизнес класса для рейса
		lag(amount, 1, amount) OVER(PARTITION BY flight_id) business_amount
		FROM amount_city_cte) q
WHERE amount > business_amount;		
--Результат нулевой. Значит не было	

-- 8. Между какими городами нет прямых рейсов?
-- Решение без представлений
-- Для начала находим всевозможные сочетания между аэропортами разных городов
with city_city_decart_cte as (
select distinct 
	lower(a.city)||' - '||lower(q.city) flight_name,
	a.city city_1, a.airport_code airport_code_1, q.city city_2, q.airport_code airport_code_2
from
	bookings.airports a
	cross join (select airport_code, city from bookings.airports) q
where
	a.airport_code != q.airport_code and a.city != q.city
order by flight_name),
-- Находим фактические сочетания между аэропортами разных городов
city_city_fact_cte as (
select distinct 
	lower(city_1)||' - '||lower(city) flight_name,
	city_1, airport_code_1, city city_2, airport_code_2
from (
	select city city_1, q1.departure_airport airport_code_1, q1.arrival_airport airport_code_2
	from bookings.airports
	join (
		select departure_airport, arrival_airport
		from bookings.flights) q1
	on departure_airport = airport_code) q2
join bookings.airports on airport_code_2 = airport_code
order by flight_name)
-- Находим рейсы не вошедшие в декартово сочетание
-- Это и будут варианты, между которыми нет сообщений								  
select initcap(flight_name) flight_name
from city_city_decart_cte
except select initcap(flight_name) from city_city_fact_cte
order by 1;

-- 8. Вариант с представлениями
-- Для начала находим возможные декартовы сочетания между аэропортами разных городов
create view city_city_decart_view as 
select distinct 
	lower(a.city)||' - '||lower(q.city) flight_name,
	a.city city_1, a.airport_code airport_code_1, q.city city_2, q.airport_code airport_code_2
from
	bookings.airports a
	cross join (select airport_code, city from bookings.airports) q
where
	a.airport_code != q.airport_code and a.city != q.city
order by flight_name;

-- Находим фактические сочетания между аэропортами разных городов
create view city_city_fact_view as
select distinct 
	lower(city_1)||' - '||lower(city) flight_name,
	city_1, airport_code_1, city city_2, airport_code_2
from (
	select city city_1, q1.departure_airport airport_code_1, q1.arrival_airport airport_code_2
	from bookings.airports
	join (
		select departure_airport, arrival_airport
		from bookings.flights) q1
	on departure_airport = airport_code) q2
join bookings.airports on airport_code_2 = airport_code
order by flight_name;

-- Находим рейсы не вошедшие в декартово сочетание
-- Это и будут варианты, между которыми нет сообщений								  
select initcap(flight_name) flight_name from city_city_decart_view
except select initcap(flight_name) flight_name from city_city_fact_view
order by 1;
-- Другой вариант
select city_1, city_2 from city_city_decart_view
except select city_1, city_2 from city_city_fact_view
order by city_1, city_2;

/*
9.Вычислите расстояние между аэропортами, связанными прямыми рейсами,
сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы */
-- Используем ранее созданное представление city_city_fact_view. На основе него создаем cte.
-- Можно сделать и без ранее созданного представления, просто тогда cte будет включать в себя его логику
-- В итоговом запросе добавляем информацию из таблицы aircraft
								  
WITH initial_data AS -- получаем исходные данные для дальнейшей работы
(
SELECT
	initcap(flight_name) flight_name,
	airport_code_1, a1.longitude lg1, a1.latitude lt1,
	airport_code_2, a2.longitude lg2, a2.latitude lt2	
FROM 
	city_city_fact_view c
	JOIN airports a1 ON c.airport_code_1 = a1.airport_code
	JOIN airports a2 ON c.airport_code_2 = a2.airport_code
),
dist_cte_rad AS --получаем расстояние в радианах
(
SELECT *,
acos(sind(lt1)*sind(lt2) + cosd(lt1)*cosd(lt2)*cosd(lg1 - lg2)) dist_rad
FROM initial_data
),
dist_cte_km AS --получаем расстояние в км
(
SELECT
	flight_name,
	airport_code_1, lg1, lt1,
	airport_code_2, lg2, lt2,
	round(6371*dist_rad::NUMERIC, 0) dist_km
FROM dist_cte_rad
)
SELECT DISTINCT 
	flight_name, dist_km,
	"range",
	CASE
		WHEN "range" >= dist_km THEN 'Успех'
		ELSE 'Провал'
	END	Результат
FROM
	dist_cte_km
	JOIN bookings.flights f --добавляем информацию из bookings.aircrafts
		ON airport_code_1 = f.departure_airport
		and airport_code_2 = f.arrival_airport
	JOIN bookings.aircrafts a USING (aircraft_code)
ORDER BY flight_name;
	 
--Вариант без представления

WITH city_city_fact_cte AS -- Находим фактические сочетания между аэропортами разных городов
(
SELECT DISTINCT
	lower(city_1)||' - '||lower(city) flight_name,
	city_1, airport_code_1, city city_2, airport_code_2
from (
	select city city_1, q1.departure_airport airport_code_1, q1.arrival_airport airport_code_2
	from bookings.airports
	join (
		select departure_airport, arrival_airport
		from bookings.flights) q1
	on departure_airport = airport_code) q2
join bookings.airports on airport_code_2 = airport_code
order by flight_name
),
initial_data AS -- получаем исходные данные для дальнейшей работы
(
SELECT
	initcap(flight_name) flight_name,
	airport_code_1, a1.longitude lg1, a1.latitude lt1,
	airport_code_2, a2.longitude lg2, a2.latitude lt2	
FROM 
	city_city_fact_cte c
	JOIN airports a1 ON c.airport_code_1 = a1.airport_code
	JOIN airports a2 ON c.airport_code_2 = a2.airport_code
),
dist_cte_rad AS --получаем расстояние в радианах
(
SELECT *,
acos(sind(lt1)*sind(lt2) + cosd(lt1)*cosd(lt2)*cosd(lg1 - lg2)) dist_rad
FROM initial_data
),
dist_cte_km AS --получаем расстояние в км
(
SELECT
	flight_name,
	airport_code_1, lg1, lt1,
	airport_code_2, lg2, lt2,
	round(6371*dist_rad::NUMERIC, 0) dist_km
FROM dist_cte_rad
)
SELECT DISTINCT 
	flight_name, dist_km,
	"range",
	CASE
		WHEN "range" >= dist_km THEN 'Успех'
		ELSE 'Провал'
	END	Результат
FROM
	dist_cte_km
	JOIN bookings.flights f --добавляем информацию из bookings.aircrafts
		ON airport_code_1 = f.departure_airport
		and airport_code_2 = f.arrival_airport
	JOIN bookings.aircrafts a USING (aircraft_code)
ORDER BY flight_name;
