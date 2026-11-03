USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.SchemaMigrations
    WHERE Numero = 46
)
    THROW 78300, 'Ejecute primero la migracion 046.', 1;
GO

DECLARE @RolCliente INT = (
    SELECT IDRol
    FROM dbo.Roles
    WHERE Nombre = 'Cliente'
);

DECLARE @CorreoA NVARCHAR(254) =
    CONCAT(N'prueba-a-', REPLACE(
        CONVERT(NVARCHAR(36), NEWID()), N'-', N''
    ), N'@shopcart.test');

DECLARE @CorreoB NVARCHAR(254) =
    CONCAT(N'prueba-b-', REPLACE(
        CONVERT(NVARCHAR(36), NEWID()), N'-', N''
    ), N'@shopcart.test');

DECLARE @Hash NVARCHAR(255) =
    N'$2b$12$' + REPLICATE(N'A', 53);

DECLARE @UsuarioA INT;
DECLARE @UsuarioB INT;
DECLARE @DireccionA INT;

DECLARE @Resultado TABLE (
    IDDireccion INT,
    Destinatario NVARCHAR(150),
    Telefono NVARCHAR(25),
    Departamento NVARCHAR(100),
    Municipio NVARCHAR(100),
    DireccionLinea1 NVARCHAR(250),
    Referencia NVARCHAR(250),
    Activa BIT,
    FechaCreacion DATETIME2(3)
);

IF @RolCliente IS NULL
    THROW 78301, 'No existe el rol Cliente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Usuarios (
        IDRol, Correo, PasswordHash
    )
    VALUES (@RolCliente, @CorreoA, @Hash);

    SET @UsuarioA = SCOPE_IDENTITY();

    INSERT INTO dbo.Usuarios (
        IDRol, Correo, PasswordHash
    )
    VALUES (@RolCliente, @CorreoB, @Hash);

    SET @UsuarioB = SCOPE_IDENTITY();

    -- Crear direccion para cliente A.
    EXEC dbo.SP_Direcciones_CrearCliente
        @IDUsuario = @UsuarioA,
        @Destinatario = N'Cliente Prueba A',
        @Telefono = N'55551234',
        @Departamento = N'Solola',
        @Municipio = N'Solola',
        @DireccionLinea1 = N'Zona 1, casa 10',
        @Referencia = N'Cerca del parque';

    SELECT @DireccionA = IDDireccion
    FROM dbo.Direcciones
    WHERE IDUsuario = @UsuarioA;

    IF @DireccionA IS NULL
        THROW 78302, 'No se creo la direccion.', 1;

    -- El propietario puede consultarla.
    INSERT INTO @Resultado
    EXEC dbo.SP_Direcciones_ObtenerCliente
        @IDUsuario = @UsuarioA,
        @IDDireccion = @DireccionA;

    IF (SELECT COUNT(*) FROM @Resultado) <> 1
        THROW 78303,
            'El propietario no puede consultar.', 1;

    DELETE FROM @Resultado;

    -- Otro cliente no puede verla.
    INSERT INTO @Resultado
    EXEC dbo.SP_Direcciones_ObtenerCliente
        @IDUsuario = @UsuarioB,
        @IDDireccion = @DireccionA;

    IF EXISTS (SELECT 1 FROM @Resultado)
        THROW 78304,
            'Se expuso una direccion ajena.', 1;

    DELETE FROM @Resultado;

    -- Otro cliente no puede listarla.
    INSERT INTO @Resultado
    EXEC dbo.SP_Direcciones_ListarCliente
        @IDUsuario = @UsuarioB;

    IF EXISTS (SELECT 1 FROM @Resultado)
        THROW 78305,
            'El cliente B ve una direccion ajena.', 1;

    DELETE FROM @Resultado;

    -- El propietario puede listarla.
    INSERT INTO @Resultado
    EXEC dbo.SP_Direcciones_ListarCliente
        @IDUsuario = @UsuarioA;

    IF (SELECT COUNT(*) FROM @Resultado) <> 1
        THROW 78306,
            'No se lista la direccion propia.', 1;

    -- Las direcciones inactivas no se listan.
    UPDATE dbo.Direcciones
    SET Activa = 0
    WHERE IDDireccion = @DireccionA;

    DELETE FROM @Resultado;

    INSERT INTO @Resultado
    EXEC dbo.SP_Direcciones_ListarCliente
        @IDUsuario = @UsuarioA;

    IF EXISTS (SELECT 1 FROM @Resultado)
        THROW 78307,
            'Se listo una direccion inactiva.', 1;

    PRINT 'OK: direcciones propias y aislamiento.';
    PRINT 'OK: filtrado de direcciones inactivas.';

    ROLLBACK TRANSACTION;

    SELECT
        'OK: pruebas RF-06 completadas' AS Resultado,
        'OK: cambios revertidos' AS Integridad;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
