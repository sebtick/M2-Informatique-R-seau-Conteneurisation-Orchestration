--
-- PostgreSQL database cluster dump
--

\restrict lvIPD72Zet9RE61h4V8OEEGpnQypyFglFeExK1nAgLlT1cPsYHZ9CEiSCMcKphF

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:EuaAFEYA1w+GWVkyjOdlEQ==$xPQErKrL0y2x9oWqFtDiE86HUxPgBdfXc7Odx8SRs3M=:39uGeJCMbHNDYxGjjyjeWGdXFrZ4e19QBgDpwLk1yf4=';

--
-- User Configurations
--








\unrestrict lvIPD72Zet9RE61h4V8OEEGpnQypyFglFeExK1nAgLlT1cPsYHZ9CEiSCMcKphF

--
-- Databases
--

--
-- Database "template1" dump
--

\connect template1

--
-- PostgreSQL database dump
--

\restrict A7Ff8w4cQtH6KpsI0BLr3mrbXeecHQiQpam7wTImOHDBkgOAK1nSooaFg5ncZAo

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 16.10 (Debian 16.10-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict A7Ff8w4cQtH6KpsI0BLr3mrbXeecHQiQpam7wTImOHDBkgOAK1nSooaFg5ncZAo

--
-- Database "postgres" dump
--

\connect postgres

--
-- PostgreSQL database dump
--

\restrict eb8t29KzRFBIfevCMrOJay4MJutUJNH0GI3aO3EE2KvQC3nN8gTgk92vKbsS5Z8

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 16.10 (Debian 16.10-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict eb8t29KzRFBIfevCMrOJay4MJutUJNH0GI3aO3EE2KvQC3nN8gTgk92vKbsS5Z8

--
-- Database "s5" dump
--

--
-- PostgreSQL database dump
--

\restrict Fex5WUOKePPZD6Z6Ir06JbHaIcU6NgtbjZZDDV2nzofqc5CNDlIrfaPHhRE95g3

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 16.10 (Debian 16.10-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: s5; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE s5 WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'en_US.utf8';


ALTER DATABASE s5 OWNER TO postgres;

\unrestrict Fex5WUOKePPZD6Z6Ir06JbHaIcU6NgtbjZZDDV2nzofqc5CNDlIrfaPHhRE95g3
\connect s5
\restrict Fex5WUOKePPZD6Z6Ir06JbHaIcU6NgtbjZZDDV2nzofqc5CNDlIrfaPHhRE95g3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: demo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.demo (
    id integer NOT NULL,
    msg text
);


ALTER TABLE public.demo OWNER TO postgres;

--
-- Data for Name: demo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.demo (id, msg) FROM stdin;
1	hello-persist
\.


--
-- Name: demo demo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.demo
    ADD CONSTRAINT demo_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict Fex5WUOKePPZD6Z6Ir06JbHaIcU6NgtbjZZDDV2nzofqc5CNDlIrfaPHhRE95g3

--
-- PostgreSQL database cluster dump complete
--

