-- Run as an Azure SQL administrator after infrastructure deployment.
-- Replace the app service name with the managed identity display name output by deployment.
IF OBJECT_ID('dbo.Orders', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Orders
    (
        Id nvarchar(64) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
        CustomerId nvarchar(128) NOT NULL,
        Sku nvarchar(128) NOT NULL,
        Quantity int NOT NULL,
        Status nvarchar(64) NOT NULL,
        CreatedUtc datetimeoffset NOT NULL
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'app_order_writer')
BEGIN
    CREATE ROLE [app_order_writer];
END;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'app-REPLACE-WITH-APP-SERVICE-NAME')
BEGIN
    CREATE USER [app-REPLACE-WITH-APP-SERVICE-NAME] FROM EXTERNAL PROVIDER;
END;

GRANT INSERT ON OBJECT::dbo.Orders TO [app_order_writer];
ALTER ROLE [app_order_writer] ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
