@echo off
rem usage: t 2 or t 3 -d
nmake /nologo
if "%2"=="-d" perl %2 %3 %4 -Mblib t\0%1*.t
if not "%2"=="-d" perl %2 %3 %4 -Mblib -MTest::Harness -e "runtests @ARGV" t\0%1*.t
