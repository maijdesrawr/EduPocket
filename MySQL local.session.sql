create table records(
    StudentNum int not null primary key,
    FullName varchar(100),
    Balance float,
    Year_Level varchar(50)
);

select * from records;

insert into records(StudentNum, FullName, Balance, Year_Level)
values
('123','Jam Cruz', '200', '3rd Year College'),
('456','John Jose', '100', '2nd Year College');