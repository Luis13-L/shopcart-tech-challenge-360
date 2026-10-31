
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations
        WHERE Numero = 23
    )
        THROW 65600,
            'Primero ejecute la migracion 023.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 24
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Inventario_ReservarExistencia', N'P'
        ) IS NOT NULL
            THROW 65601,
                'El procedimiento ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Inventario_ReservarExistencia
    @IDCarrito BIGINT,
    @IDUsuario INT,
    @IDReserva BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @IDReserva = NULL;

    IF @IDCarrito IS NULL OR @IDCarrito <= 0
        THROW 65602, ''Carrito invalido.'', 1;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 65603, ''Usuario invalido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Validar que sea un cliente activo.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            JOIN dbo.Roles r ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario
              AND u.Activo = 1
              AND r.Nombre = ''Cliente''
        )
            THROW 65604,
                ''Cliente no autorizado.'', 1;

        -- 2. Bloquear el carrito y comprobar propiedad.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Carritos WITH (UPDLOCK, HOLDLOCK)
            WHERE IDCarrito = @IDCarrito
              AND IDUsuario = @IDUsuario
              AND Estado = ''ACTIVO''
        )
            THROW 65605,
                ''Carrito no disponible para este cliente.'',
                1;

        -- 3. Capturar el contenido del carrito.
        -- HOLDLOCK mantiene bloqueado el conjunto
        -- durante la transaccion.
        CREATE TABLE #Lineas (
            IDVariante INT NOT NULL PRIMARY KEY,
            Cantidad INT NOT NULL
        );

        INSERT INTO #Lineas (
            IDVariante,
            Cantidad
        )
        SELECT
            d.IDVariante,
            d.Cantidad
        FROM dbo.DetallesCarrito d WITH (HOLDLOCK)
        WHERE d.IDCarrito = @IDCarrito;

        IF NOT EXISTS (SELECT 1 FROM #Lineas)
            THROW 65606,
                ''No se puede reservar un carrito vacio.'',
                1;

        -- 4. Validar productos vendibles.
        IF EXISTS (
            SELECT 1
            FROM #Lineas l
            LEFT JOIN dbo.Variantes v
                ON v.IDVariante = l.IDVariante
            LEFT JOIN dbo.Productos p
                ON p.IDProducto = v.IDProducto
            LEFT JOIN dbo.Categorias c
                ON c.IDCategoria = p.IDCategoria
            WHERE l.Cantidad <= 0
               OR v.IDVariante IS NULL
               OR v.Activa <> 1
               OR p.IDProducto IS NULL
               OR p.Activo <> 1
               OR c.IDCategoria IS NULL
               OR c.Activa <> 1
        )
            THROW 65607,
                ''El carrito contiene productos no disponibles.'',
                1;

        -- 5. Consultar reserva ACTIVA del mismo carrito.
        DECLARE @ReservaExistente BIGINT = NULL;
        DECLARE @Vence DATETIME2(3);

        SELECT
            @ReservaExistente = IDReserva,
            @Vence = ExpiraEn
        FROM dbo.ReservasInventario
            WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCarrito = @IDCarrito
          AND Estado = ''ACTIVA'';

        IF @ReservaExistente IS NOT NULL
        BEGIN
            IF @Vence <= SYSUTCDATETIME()
            BEGIN
                -- La reserva vencida ya no aparta stock.
                UPDATE dbo.ReservasInventario
                SET Estado = ''VENCIDA'',
                    FechaCierre = SYSUTCDATETIME()
                WHERE IDReserva = @ReservaExistente;

                SET @ReservaExistente = NULL;
            END
            ELSE
            BEGIN
                -- Idempotencia: verificar que el carrito
                -- no haya cambiado desde la reserva.
                IF EXISTS (
                    SELECT 1
                    FROM #Lineas l
                    FULL OUTER JOIN (
                        SELECT IDVariante, Cantidad
                        FROM dbo.DetallesReserva
                        WHERE IDReserva = @ReservaExistente
                    ) d ON d.IDVariante = l.IDVariante
                    WHERE l.IDVariante IS NULL
                       OR d.IDVariante IS NULL
                       OR l.Cantidad <> d.Cantidad
                )
                    THROW 65608,
                        ''El carrito cambio durante la reserva vigente.'',
                        1;

                SET @IDReserva = @ReservaExistente;

                COMMIT TRANSACTION;
                RETURN;
            END;
        END;

        -- 6. Bloquear las filas de existencia en
        -- orden ascendente para evitar sobreventa.
        DECLARE @UltimaVariante INT = 0;
        DECLARE @Variante INT;
        DECLARE @Cantidad INT;
        DECLARE @Fisica INT;
        DECLARE @Reservadas BIGINT;

        WHILE EXISTS (
            SELECT 1 FROM #Lineas
            WHERE IDVariante > @UltimaVariante
        )
        BEGIN
            SELECT TOP (1)
                @Variante = IDVariante,
                @Cantidad = Cantidad
            FROM #Lineas
            WHERE IDVariante > @UltimaVariante
            ORDER BY IDVariante;

            SET @Fisica = NULL;

            SELECT @Fisica = CantidadFisica
            FROM dbo.Existencias WITH (
                UPDLOCK,
                HOLDLOCK
            )
            WHERE IDVariante = @Variante;

            IF @Fisica IS NULL
                THROW 65609,
                    ''La variante no tiene inventario.'',
                    1;

            -- Solo contar reservas vigentes.
            SELECT @Reservadas =
                ISNULL(
                    SUM(CONVERT(BIGINT, dr.Cantidad)),
                    0
                )
            FROM dbo.DetallesReserva dr
            INNER JOIN dbo.ReservasInventario r
                ON r.IDReserva = dr.IDReserva
            WHERE dr.IDVariante = @Variante
              AND r.Estado = ''ACTIVA''
              AND r.ExpiraEn > SYSUTCDATETIME();

            IF CONVERT(BIGINT, @Fisica) -
               @Reservadas < @Cantidad
                THROW 65610,
                    ''Existencias disponibles insuficientes.'',
                    1;

            SET @UltimaVariante = @Variante;
        END;

        -- 7. Crear la reserva de 15 minutos.
        DECLARE @Inicio DATETIME2(3) =
            SYSUTCDATETIME();

        INSERT INTO dbo.ReservasInventario (
            IDCarrito,
            IDUsuario,
            Estado,
            FechaCreacion,
            ExpiraEn
        )
        VALUES (
            @IDCarrito,
            @IDUsuario,
            ''ACTIVA'',
            @Inicio,
            DATEADD(MINUTE, 15, @Inicio)
        );

        SET @IDReserva =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -- 8. Reservar cada variante del carrito.
        INSERT INTO dbo.DetallesReserva (
            IDReserva,
            IDVariante,
            Cantidad
        )
        SELECT
            @IDReserva,
            IDVariante,
            Cantidad
        FROM #Lineas;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- La API ejecutara el procedimiento.
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Inventario_ReservarExistencia
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            24,
            N'024_InventoryReserveProcedure'
        );

        PRINT 'Migracion 024 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Inventario_ReservarExistencia', N'P'
        ) IS NULL
            THROW 65611,
                'Migracion registrada sin procedimiento.', 1;

        PRINT 'Migracion 024 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
