
-- ================================================
-- PROYECTO: ShopCart
-- MIGRACION: 001_CreateDatabase.sql
-- OBJETIVO: Crear la base de datos principal
-- MOTOR: Microsoft SQL Server 2019+
-- ================================================

USE master;
GO

-- Verificar si la base de datos ya existe
IF DB_ID(N'ShopCartDB') IS NULL
BEGIN
    CREATE DATABASE ShopCartDB;

    PRINT 'Base de datos ShopCartDB creada correctamente.';
END
ELSE
BEGIN
    PRINT 'La base de datos ShopCartDB ya existe.';
END;
GO

-- Verificar la base de datos creada
SELECT
    name AS NombreBaseDatos,
    state_desc AS Estado,
    compatibility_level AS NivelCompatibilidad,
    recovery_model_desc AS ModeloRecuperacion
FROM sys.databases
WHERE name = N'ShopCartDB';
GO
