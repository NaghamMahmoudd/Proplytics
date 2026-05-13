-- ============================================================
-- 1. Sales Performance Report
--    Viewers: Manager, Team Leader
--    Shows: units sold, revenue, target comparison per agent/team
-- ============================================================
ALTER PROCEDURE sp_SalesPerformanceReport
    @StartDate    DATE = NULL,
    @EndDate      DATE = NULL,
    @AgentID      INT  = NULL,   -- NULL = all agents
    @TeamLeaderID INT  = NULL,   -- NULL = all teams
    @ProjectID    INT  = NULL    -- NULL = all projects
AS
BEGIN
    SET NOCOUNT ON;
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());

    SELECT
        sa.AgentID,
        sa.FirstName + ' ' + sa.LastName     AS AgentName,
        tl.TeamLeaderID,
        tl.FirstName + ' ' + tl.LastName     AS TeamLeaderName,
        p.ProjectID,
        p.ProjectName,
        COUNT(DISTINCT d.DealID)              AS UnitsSold,
        SUM(d.TotalAmount)                    AS TotalRevenue,
        sa.TargetUnits                        AS AgentTargetUnits,
        sa.TargetAmount                       AS AgentTargetAmount,
        CASE 
            WHEN sa.TargetUnits > 0 
            THEN CAST(COUNT(DISTINCT d.DealID) * 100.0 / sa.TargetUnits AS DECIMAL(5,2))
            ELSE NULL 
        END                                   AS UnitAchievementPct,
        CASE 
            WHEN sa.TargetAmount > 0 
            THEN CAST(SUM(d.TotalAmount) * 100.0 / sa.TargetAmount AS DECIMAL(5,2))
            ELSE NULL 
        END                                   AS RevenueAchievementPct
    FROM Deal d
    INNER JOIN Reservation r  ON d.ReservationID = r.ReservationID
    INNER JOIN SalesAgent  sa ON r.AgentID        = sa.AgentID
    INNER JOIN Property    pr ON r.PropertyID     = pr.PropertyID
    INNER JOIN Project     p  ON pr.ProjectID     = p.ProjectID
    LEFT  JOIN TeamLeader  tl ON sa.TeamLeaderID  = tl.TeamLeaderID
    WHERE d.Status IN ('Completed', 'Active')
      AND d.ContractDate BETWEEN @StartDate AND @EndDate
      AND (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
      AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)
      AND (@ProjectID    IS NULL OR p.ProjectID     = @ProjectID)
    GROUP BY
        sa.AgentID, sa.FirstName, sa.LastName, sa.TargetUnits, sa.TargetAmount,
        tl.TeamLeaderID, tl.FirstName, tl.LastName,
        p.ProjectID, p.ProjectName
    ORDER BY TotalRevenue DESC;
END;
GO

EXEC sp_SalesPerformanceReport

EXEC sp_SalesPerformanceReport    @StartDate = '2018-09-28',     @EndDate   = '2025-12-31';

EXEC sp_SalesPerformanceReport    @StartDate = '2020-09-28',     @EndDate   = '2025-12-31',     @AgentID   = 7;

-- ============================================================
-- 2. Payment Collection Report
--    Viewers: Manager, Finance Department
--    Shows: installments, paid/remaining balances, overdue
-- ============================================================
ALTER PROCEDURE sp_PaymentCollectionReport
    @StartDate   DATE = NULL,
    @EndDate     DATE = NULL,
    @ProjectID   INT  = NULL,
    @OverdueOnly BIT  = 0      -- 1 = return only overdue customers
AS
BEGIN
    SET NOCOUNT ON;
 
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), 1, 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());
 
    SELECT
        c.CustomerID,
        c.FirstName + ' ' + c.LastName            AS CustomerName,
        c.Phone                                    AS CustomerPhone,
        c.Email                                    AS CustomerEmail,
        d.DealID,
        d.ContractDate,
        d.TotalAmount,
        d.DownPayment,
        d.DealType,
        d.ContractType,
        pr.Title                                   AS PropertyTitle,
        p.ProjectName,
 
        -- Aggregated payment info
        SUM(CASE WHEN pay.Status = 'Paid' THEN pay.Amount ELSE 0 END)
                                                   AS TotalPaid,
        SUM(CASE WHEN pay.Status <> 'Paid' THEN pay.Amount ELSE 0 END)
                                                   AS RemainingBalance,
        SUM(CASE
                WHEN pay.Status <> 'Paid' AND pay.DueDate < GETDATE()
                THEN pay.Amount ELSE 0
            END)                                   AS OverdueAmount,
        MAX(CASE
                WHEN pay.Status <> 'Paid' AND pay.DueDate < GETDATE()
                THEN pay.DueDate
            END)                                   AS EarliestOverdueDueDate,
        COUNT(CASE WHEN pay.Status <> 'Paid' AND pay.DueDate < GETDATE()
                   THEN 1 END)                     AS OverdueInstallments,
        COUNT(pay.PaymentID)                       AS TotalInstallments,
        COUNT(CASE WHEN pay.Status = 'Paid' THEN 1 END) AS PaidInstallments
 
    FROM Deal d
    INNER JOIN Reservation  res ON d.ReservationID = res.ReservationID
    INNER JOIN Customer     c   ON res.CustomerID  = c.CustomerID
    INNER JOIN Property     pr  ON res.PropertyID  = pr.PropertyID
    INNER JOIN Project      p   ON pr.ProjectID    = p.ProjectID
    LEFT  JOIN Payment      pay ON pay.DealID      = d.DealID
    WHERE (@ProjectID IS NULL OR p.ProjectID = @ProjectID)
      AND d.ContractDate BETWEEN @StartDate AND @EndDate
    GROUP BY
        c.CustomerID, c.FirstName, c.LastName, c.Phone, c.Email,
        d.DealID, d.ContractDate, d.TotalAmount, d.DownPayment,
        d.DealType, d.ContractType,
        pr.Title, p.ProjectName
    HAVING
        -- if OverdueOnly flag is set, return only customers with overdue payments
        @OverdueOnly = 0
        OR SUM(CASE
                   WHEN pay.Status <> 'Paid' AND pay.DueDate < GETDATE()
                   THEN pay.Amount ELSE 0
               END) > 0
    ORDER BY OverdueAmount DESC, CustomerName;
END;
GO

exec sp_PaymentCollectionReport   @StartDate = '2020-01-01', @EndDate = '2025-12-31', @OverdueOnly = 0;

-- ========================================================================================================================
-- 3. Property Inventory & Status Report
--    Viewers: Manager, Team Leader
--    Shows: all units with status, classified by project/type/location
-- ========================================================================================================================
CREATE PROCEDURE sp_PropertyInventoryReport

    @ProjectID  INT          = NULL,
    @LocationID INT          = NULL,
    @TypeID     INT          = NULL,
    @Status     VARCHAR(50)  = NULL   -- 'Available','Reserved','Sold','Rented' or NULL = all
AS
BEGIN

    SET NOCOUNT ON;
 
    SELECT
        pr.PropertyID,
        pr.Title,
        p.ProjectName,
        loc.City,
        loc.District,
        pt.TypeName                                AS PropertyType,
        pr.Status,
        pr.Price,
        pr.Size,
        pr.Bedrooms,
        pr.Bathrooms,
        pr.FloorLevel,
        pr.ViewType,
        pr.FinishingType,
        pr.DeliveryType,
        pr.DeliveryDate,
        pr.Parking,
        pr.HasGarden,
        pr.Furnished,
        pr.HasPool,
        -- Reservation info if reserved/sold
        res.ReservationDate,
        res.ExpiryDate,
        res.Status                                 AS ReservationStatus,
        c.FirstName + ' ' + c.LastName             AS CustomerName,
        c.Phone                                    AS CustomerPhone
    FROM Property pr
    INNER JOIN Project      p   ON pr.ProjectID  = p.ProjectID
    INNER JOIN Location     loc ON pr.LocationID = loc.LocationID
    INNER JOIN PropertyType pt  ON pr.TypeID     = pt.TypeID
    LEFT  JOIN Reservation  res ON res.PropertyID = pr.PropertyID
                                AND res.Status NOT IN ('Cancelled','Expired')
    LEFT  JOIN Customer     c   ON res.CustomerID = c.CustomerID
    WHERE (@ProjectID  IS NULL OR pr.ProjectID  = @ProjectID)
      AND (@LocationID IS NULL OR pr.LocationID = @LocationID)
      AND (@TypeID     IS NULL OR pr.TypeID     = @TypeID)
      AND (@Status     IS NULL OR pr.Status     = @Status)
    ORDER BY p.ProjectName, pt.TypeName, pr.Status, pr.Price;
END;
GO
exec sp_PropertyInventoryReport  @LocationID = 930, @TypeID = 12, @Status = 'Available';

-- ============================================================
-- 4. Agent Commission Report
--    Viewers: Manager, Finance Department
--    Shows: commission per agent on completed deals
-- ============================================================
CREATE PROCEDURE sp_AgentCommissionReport
    @StartDate    DATE = NULL,
    @EndDate      DATE = NULL,
    @AgentID      INT  = NULL,
    @TeamLeaderID INT  = NULL
AS
BEGIN
    SET NOCOUNT ON;
 
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());
 
    SELECT
        sa.AgentID,
        sa.FirstName + ' ' + sa.LastName           AS AgentName,
        sa.Email                                    AS AgentEmail,
        sa.Phone                                    AS AgentPhone,
        tl.FirstName + ' ' + tl.LastName           AS TeamLeaderName,
        at.AgentTypeName,
        at.CommissionRate,
 
        COUNT(d.DealID)                             AS TotalDeals,
        SUM(d.TotalAmount)                          AS TotalDealValue,
        SUM(d.TotalAmount * at.CommissionRate / 100) AS TotalCommissionEarned,
 
        -- Rank agents by commission within the result set
        RANK() OVER (ORDER BY SUM(d.TotalAmount * at.CommissionRate / 100) DESC)
                                                    AS CommissionRank
 
    FROM Deal d
    INNER JOIN Reservation  res ON d.ReservationID = res.ReservationID
    INNER JOIN SalesAgent   sa  ON res.AgentID     = sa.AgentID
    INNER JOIN AgentType    at  ON sa.AgentTypeID  = at.AgentTypeID
    LEFT  JOIN TeamLeader   tl  ON sa.TeamLeaderID = tl.TeamLeaderID
    WHERE d.Status        = 'Completed'
      AND d.ContractDate  BETWEEN @StartDate AND @EndDate
      AND (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
      AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)
    GROUP BY
        sa.AgentID, sa.FirstName, sa.LastName, sa.Email, sa.Phone,
        tl.FirstName, tl.LastName,
        at.AgentTypeName, at.CommissionRate
    ORDER BY TotalCommissionEarned DESC;
END;
GO
exec sp_AgentCommissionReport   @StartDate = '2020-01-01', @EndDate = '2025-12-31';

-- ============================================================
-- 5. Project Revenue Report
--    Viewers: Manager
--    Shows: actual vs expected revenue, sold % and remaining units
-- ============================================================
CREATE PROCEDURE sp_ProjectRevenueReport
    @ProjectID INT  = NULL,
    @Status    VARCHAR(50) = NULL    -- 'Active','Completed', etc. or NULL = all
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        p.ProjectID,
        p.ProjectName,
        p.Status                                    AS ProjectStatus,
        p.StartDate,
        p.EndDate,
        p.TotalUnits,
        loc.City,
        loc.District,
 
        -- Unit breakdown
        COUNT(pr.PropertyID)                        AS ListedUnits,
        COUNT(CASE WHEN pr.Status = 'Available' THEN 1 END) AS AvailableUnits,
        COUNT(CASE WHEN pr.Status = 'Reserved'  THEN 1 END) AS ReservedUnits,
        COUNT(CASE WHEN pr.Status = 'Sold'      THEN 1 END) AS SoldUnits,
        COUNT(CASE WHEN pr.Status = 'Rented'    THEN 1 END) AS RentedUnits,
 
        -- Revenue
        SUM(pr.Price)                               AS ProjectedTotalRevenue,
        ISNULL(SUM(CASE WHEN pr.Status IN ('Sold','Rented')
                        THEN d.TotalAmount END), 0) AS ActualRevenue,
        SUM(pr.Price) - ISNULL(SUM(CASE WHEN pr.Status IN ('Sold','Rented')
                                         THEN d.TotalAmount END), 0)
                                                    AS RemainingExpectedRevenue,
        -- Sold %
        CASE
            WHEN COUNT(pr.PropertyID) > 0
            THEN CAST(COUNT(CASE WHEN pr.Status = 'Sold' THEN 1 END) * 100.0
                      / COUNT(pr.PropertyID) AS DECIMAL(5,2))
            ELSE 0
        END                                         AS SoldPct,
 
        -- Revenue achievement %
        CASE
            WHEN SUM(pr.Price) > 0
            THEN CAST(ISNULL(SUM(CASE WHEN pr.Status IN ('Sold','Rented')
                                      THEN d.TotalAmount END), 0) * 100.0
                      / SUM(pr.Price) AS DECIMAL(5,2))
            ELSE 0
        END                                         AS RevenueAchievementPct
 
    FROM Project p
    INNER JOIN Location  loc ON p.LocationID  = loc.LocationID
    LEFT  JOIN Property  pr  ON pr.ProjectID  = p.ProjectID
    LEFT  JOIN Reservation res ON res.PropertyID = pr.PropertyID
                               AND res.Status NOT IN ('Cancelled','Expired')
    LEFT  JOIN Deal      d   ON d.ReservationID = res.ReservationID
                             AND d.Status = 'Completed'
    WHERE (@ProjectID IS NULL OR p.ProjectID = @ProjectID)
      AND (@Status    IS NULL OR p.Status    = @Status)
    GROUP BY
        p.ProjectID, p.ProjectName, p.Status, p.StartDate, p.EndDate,
        p.TotalUnits, loc.City, loc.District
    ORDER BY ActualRevenue DESC;
END;
GO

EXEC sp_ProjectRevenueReport   @Status = 'Completed';
EXEC sp_ProjectRevenueReport   @ProjectID = 15;

-- ============================================================
-- 6. Property Demand Report
--    Viewers: Manager, Team Leader
--    Shows: highest demand by property type, location, and view type
--           based on completed deals
-- ============================================================
CREATE PROCEDURE sp_PropertyDemandReport
    @ProjectID  INT  = NULL,
    @StartDate  DATE = NULL,
    @EndDate    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
 
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), 1, 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());
 
    -- Demand by Property Type
    SELECT
        'ByType'                                   AS ReportSection,
        pt.TypeName                                AS GroupLabel,
        NULL                                       AS City,
        NULL                                       AS District,
        NULL                                       AS ViewType,
        COUNT(d.DealID)                            AS TotalDeals,
        SUM(d.TotalAmount)                         AS TotalRevenue,
        AVG(pr.Price)                              AS AvgPropertyPrice,
        AVG(pr.Size)                               AS AvgPropertySize
    FROM Deal d
    INNER JOIN Reservation  res ON d.ReservationID = res.ReservationID
    INNER JOIN Property     pr  ON res.PropertyID  = pr.PropertyID
    INNER JOIN PropertyType pt  ON pr.TypeID       = pt.TypeID
    INNER JOIN Project      p   ON pr.ProjectID    = p.ProjectID
    WHERE d.Status = 'Completed'
      AND d.ContractDate BETWEEN @StartDate AND @EndDate
      AND (@ProjectID IS NULL OR pr.ProjectID = @ProjectID)
    GROUP BY pt.TypeName
 
    UNION ALL
 
    -- Demand by Location
    SELECT
        'ByLocation',
        loc.City + ' - ' + loc.District,
        loc.City,
        loc.District,
        NULL,
        COUNT(d.DealID),
        SUM(d.TotalAmount),
        AVG(pr.Price),
        AVG(pr.Size)
    FROM Deal d
    INNER JOIN Reservation  res ON d.ReservationID = res.ReservationID
    INNER JOIN Property     pr  ON res.PropertyID  = pr.PropertyID
    INNER JOIN Location     loc ON pr.LocationID   = loc.LocationID
    INNER JOIN Project      p   ON pr.ProjectID    = p.ProjectID
    WHERE d.Status = 'Completed'
      AND d.ContractDate BETWEEN @StartDate AND @EndDate
      AND (@ProjectID IS NULL OR pr.ProjectID = @ProjectID)
    GROUP BY loc.City, loc.District
 
    UNION ALL
 
    -- Demand by View Type
    SELECT
        'ByViewType',
        ISNULL(pr.ViewType, 'Not Specified'),
        NULL,
        NULL,
        pr.ViewType,
        COUNT(d.DealID),
        SUM(d.TotalAmount),
        AVG(pr.Price),
        AVG(pr.Size)
    FROM Deal d
    INNER JOIN Reservation  res ON d.ReservationID = res.ReservationID
    INNER JOIN Property     pr  ON res.PropertyID  = pr.PropertyID
    INNER JOIN Project      p   ON pr.ProjectID    = p.ProjectID
    WHERE d.Status = 'Completed'
      AND d.ContractDate BETWEEN @StartDate AND @EndDate
      AND (@ProjectID IS NULL OR pr.ProjectID = @ProjectID)
    GROUP BY pr.ViewType
 
    ORDER BY ReportSection, TotalDeals DESC;
END;
GO
EXEC sp_PropertyDemandReport   @StartDate = '2020-01-01', @EndDate = '2025-12-31';
exec sp_PropertyDemandReport   @ProjectID = 15, @StartDate = '2020-01-01', @EndDate = '2025-12-31';


