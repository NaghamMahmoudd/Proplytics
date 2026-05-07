/* ============================================================
   Tracks the full customer journey per agent:
       Customer Assigned → Reservation Made → Deal Completed
   Customer is linked to Agent directly (Customer.AgentID).
   Reservation is linked to Agent (Reservation.AgentID).
   Deal is reached via Reservation (Deal.ReservationID).
   ============================================================ */
CREATE OR ALTER PROCEDURE sp_CustomerLeadFunnel
    @StartDate    DATE = NULL,
    @EndDate      DATE = NULL,
    @AgentID      INT  = NULL,
    @TeamLeaderID INT  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), 1, 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());

    BEGIN TRY

        SELECT
            sa.AgentID,
            sa.FirstName + ' ' + sa.LastName                        AS AgentName,
            at.AgentTypeID,
            tl.TeamLeaderID,
            tl.FirstName + ' ' + tl.LastName                        AS TeamLeaderName,

            COUNT(DISTINCT c.CustomerID)                             AS TotalAssignedCustomers,
            COUNT(DISTINCT res.ReservationID)                        AS TotalReservationsMade,

            COUNT(DISTINCT
                CASE WHEN d.DealID IS NOT NULL
                     THEN d.DealID END)                              AS TotalDealsCompleted,

            COUNT(DISTINCT
                CASE WHEN res.ReservationID IS NOT NULL
                          AND d.DealID IS NULL
                     THEN res.ReservationID END)                     AS OpenReservationsNoDeal,

            CASE
                WHEN COUNT(DISTINCT res.ReservationID) > 0
                THEN CAST(
                        COUNT(DISTINCT CASE WHEN d.DealID IS NOT NULL THEN d.DealID END)
                        * 100.0 / COUNT(DISTINCT res.ReservationID)
                     AS DECIMAL(5,2))
                ELSE NULL
            END                                                      AS ReservationToClosedPct,

            CASE
                WHEN COUNT(DISTINCT c.CustomerID) > 0
                THEN CAST(
                        COUNT(DISTINCT CASE WHEN d.DealID IS NOT NULL THEN d.DealID END)
                        * 100.0 / COUNT(DISTINCT c.CustomerID)
                     AS DECIMAL(5,2))
                ELSE NULL
            END                                                      AS OverallConversionPct,

            -- ✅ FIX: was DATEDIFF(DAY, res.ReservationDate, d.DealID)
            --         d.DealID is INT not DATE → use d.ContractDate
            AVG(CAST(
                DATEDIFF(DAY, res.ReservationDate, d.ContractDate) AS int)
            )                                                        AS AvgDaysReservationToClose

        FROM SalesAgent sa
        INNER JOIN AgentType   at  ON sa.AgentTypeID   = at.AgentTypeID
        LEFT  JOIN TeamLeader  tl  ON sa.TeamLeaderID  = tl.TeamLeaderID
        LEFT  JOIN Customer    c   ON c.AgentID        = sa.AgentID
                                   AND c.RegistrationDate BETWEEN @StartDate AND @EndDate
        LEFT  JOIN Reservation res ON res.AgentID      = sa.AgentID
                                   AND res.ReservationDate BETWEEN @StartDate AND @EndDate
        LEFT  JOIN Deal        d   ON d.ReservationID  = res.ReservationID

        WHERE (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
          AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)

        GROUP BY
            sa.AgentID, sa.FirstName, sa.LastName,
            at.AgentTypeID,
            tl.TeamLeaderID, tl.FirstName, tl.LastName

        ORDER BY OverallConversionPct DESC, TotalAssignedCustomers DESC;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO


Exec sp_CustomerLeadFunnel @StartDate = '2016-01-01', @EndDate = '2024-12-31',@AgentID = 10;

/* ============================================================
   Live workload snapshot per agent.
   Customers → via Customer.AgentID
   Reservations → via Reservation.AgentID
   Deals → via Deal.ReservationID → Reservation.AgentID
   ============================================================ */
CREATE PROCEDURE sp_AgentWorkload
    @TeamLeaderID INT = NULL,   -- NULL = all teams
    @AgentID      INT = NULL    -- NULL = all agents
AS
BEGIN
    SET NOCOUNT ON;
 
    BEGIN TRY
 
        SELECT
            sa.AgentID,
            sa.FirstName + ' ' + sa.LastName                        AS AgentName,
            at.AgentTypeID,
            sa.Email                                                 AS AgentEmail,
            sa.Phone                                                 AS AgentPhone,
            sa.HireDate,
            sa.TargetUnits,
            sa.TargetAmount,
            tl.TeamLeaderID,
            tl.FirstName + ' ' + tl.LastName                        AS TeamLeaderName,
 
            -- Customers assigned to this agent (all-time)
            COUNT(DISTINCT c.CustomerID)                             AS TotalAssignedCustomers,
 
            -- Customers with no reservation linked to this agent yet
            COUNT(DISTINCT
                CASE WHEN res.ReservationID IS NULL
                     THEN c.CustomerID END)                          AS CustomersWithNoReservation,
 
            -- All reservations currently held by this agent
            COUNT(DISTINCT res.ReservationID)                        AS TotalReservations,
 
            -- Reservations that have not yet produced a deal
            COUNT(DISTINCT
                CASE WHEN d.DealID IS NULL
                     THEN res.ReservationID END)                     AS OpenReservations,
 
            -- All deals linked to this agent's reservations
            COUNT(DISTINCT d.DealID)                                 AS TotalDeals,
 
            -- Total revenue from all deals through this agent
            ISNULL(SUM(d.TotalAmount), 0)                           AS TotalDealRevenue,
 
            -- Avg deal value
            AVG(d.TotalAmount)                                       AS AvgDealValue,
 
            -- Revenue achievement %
            CASE
                WHEN sa.TargetAmount > 0
                THEN CAST(
                        ISNULL(SUM(d.TotalAmount), 0) * 100.0
                        / sa.TargetAmount
                     AS DECIMAL(5,2))
                ELSE NULL
            END                                                      AS RevenueAchievementPct,
 
            -- Units achievement %
            CASE
                WHEN sa.TargetUnits > 0
                THEN CAST(
                        COUNT(DISTINCT d.DealID) * 100.0
                        / sa.TargetUnits
                     AS DECIMAL(5,2))
                ELSE NULL
            END                                                      AS UnitsAchievementPct
 
        FROM SalesAgent sa
        INNER JOIN AgentType   at  ON sa.AgentTypeID  = at.AgentTypeID
        LEFT  JOIN TeamLeader  tl  ON sa.TeamLeaderID = tl.TeamLeaderID
        LEFT  JOIN Customer    c   ON c.AgentID       = sa.AgentID
        LEFT  JOIN Reservation res ON res.AgentID     = sa.AgentID
        LEFT  JOIN Deal        d   ON d.ReservationID = res.ReservationID
 
        WHERE (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
          AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)
 
        GROUP BY
            sa.AgentID, sa.FirstName, sa.LastName,
            at.AgentTypeID,
            sa.Email, sa.Phone, sa.HireDate,
            sa.TargetUnits, sa.TargetAmount,
            tl.TeamLeaderID, tl.FirstName, tl.LastName
 
        ORDER BY TotalReservations DESC, TotalDeals DESC;
 
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
EXEC sp_AgentWorkload @TeamLeaderID = 1

/* ============================================================
   Lists reservations expiring within the next N days, or
   already expired. Reservation links to Agent and Property.
   Customer is found via Customer.AgentID = Reservation.AgentID
   ============================================================ */

CREATE OR ALTER PROCEDURE sp_ReservationExpiry
    @DaysAhead             INT = 7,
    @IncludeAlreadyExpired BIT = 1,
    @ProjectID             INT = NULL,
    @AgentID               INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        DECLARE @Today DATE = CAST(GETDATE() AS DATE);

        SELECT
            res.ReservationID,
            res.ReservationDate,
            res.ExpiryDate,

            -- Negative value = already expired (correct by design)
            DATEDIFF(DAY, @Today, res.ExpiryDate)                   AS DaysUntilExpiry,

            CASE
                WHEN res.ExpiryDate < @Today                               THEN 'Expired'
                WHEN DATEDIFF(DAY, @Today, res.ExpiryDate) <= 3            THEN 'Critical'
                WHEN DATEDIFF(DAY, @Today, res.ExpiryDate) <= @DaysAhead   THEN 'Upcoming'
                ELSE 'OK'
            END                                                      AS ExpiryUrgency,

            pr.PropertyID,
            pr.Title                                                 AS PropertyTitle,
            pr.Price                                                 AS PropertyPrice,
            pr.Status                                                AS PropertyStatus,
            pt.TypeName                                              AS PropertyType,

            p.ProjectID,
            p.ProjectName,
            loc.City,

            sa.AgentID,
            sa.FirstName + ' ' + sa.LastName                        AS AgentName,
            sa.Phone                                                 AS AgentPhone,
            sa.Email                                                 AS AgentEmail,

            tl.TeamLeaderID,
            tl.FirstName + ' ' + tl.LastName                        AS TeamLeaderName,
            tl.Phone                                                 AS TeamLeaderPhone

        FROM Reservation res
        INNER JOIN Property     pr  ON res.PropertyID   = pr.PropertyID
        INNER JOIN PropertyType pt  ON pr.TypeID        = pt.TypeID
        INNER JOIN Project      p   ON pr.ProjectID     = p.ProjectID
        INNER JOIN Location     loc ON pr.LocationID    = loc.LocationID
        INNER JOIN SalesAgent   sa  ON res.AgentID      = sa.AgentID
        LEFT  JOIN TeamLeader   tl  ON sa.TeamLeaderID  = tl.TeamLeaderID

        WHERE
            -- ✅ FIX: only active reservations (no completed/cancelled)
            res.Status = 'Active'
          AND (
                (res.ExpiryDate >= @Today
                 AND res.ExpiryDate <= DATEADD(DAY, @DaysAhead, @Today))
                OR
                (@IncludeAlreadyExpired = 1 AND res.ExpiryDate < @Today)
              )
          AND (@ProjectID IS NULL OR p.ProjectID  = @ProjectID)
          AND (@AgentID   IS NULL OR sa.AgentID   = @AgentID)

        ORDER BY
            CASE WHEN res.ExpiryDate < @Today THEN 0 ELSE 1 END,
            res.ExpiryDate ASC;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO


EXEC sp_ReservationExpiry @DaysAhead = 14, @IncludeAlreadyExpired = 1, @ProjectID = NULL, @AgentID = NULL;

/* ============================================================
   Aggregates deal and revenue data at team-leader level.
   Chain: TeamLeader → SalesAgent → Reservation → Deal
   Target columns (TargetAmount, TargetUnits) exist on
   TeamLeader directly per the ERD.
   ============================================================ */
CREATE PROCEDURE sp_TeamLeaderPerformance
    @StartDate DATE = NULL,
    @EndDate   DATE = NULL,
    @ProjectID INT  = NULL   -- NULL = all projects
AS
BEGIN
    SET NOCOUNT ON;
 
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());
 
    BEGIN TRY
 
        -- CTE: agent-level aggregates for the period
        WITH AgentStats AS (
            SELECT
                sa.AgentID,
                sa.FirstName + ' ' + sa.LastName                    AS AgentName,
                sa.TeamLeaderID,
                COUNT(DISTINCT d.DealID)                            AS AgentDeals,
                ISNULL(SUM(d.TotalAmount), 0)                       AS AgentRevenue
            FROM SalesAgent  sa
            INNER JOIN Reservation res ON res.AgentID      = sa.AgentID
                                       AND res.ReservationDate
                                           BETWEEN @StartDate AND @EndDate
            INNER JOIN Deal        d   ON d.ReservationID  = res.ReservationID
            INNER JOIN Property    pr  ON res.PropertyID   = pr.PropertyID
            WHERE (@ProjectID IS NULL OR pr.ProjectID = @ProjectID)
            GROUP BY sa.AgentID, sa.FirstName, sa.LastName, sa.TeamLeaderID
        ),
 
        -- CTE: best agent per team by revenue
        TopAgentPerTeam AS (
            SELECT
                TeamLeaderID,
                AgentName       AS TopAgentName,
                AgentRevenue    AS TopAgentRevenue,
                AgentDeals      AS TopAgentDeals,
                ROW_NUMBER() OVER (
                    PARTITION BY TeamLeaderID
                    ORDER BY AgentRevenue DESC
                )               AS RowNum
            FROM AgentStats
        )
 
        SELECT
            tl.TeamLeaderID,
            tl.FirstName + ' ' + tl.LastName                        AS TeamLeaderName,
            tl.Email                                                 AS TeamLeaderEmail,
            tl.Phone                                                 AS TeamLeaderPhone,
            tl.TargetAmount,
            tl.TargetUnits,
 
            -- Number of agents under this team leader
            COUNT(DISTINCT sa.AgentID)                               AS AgentCount,
 
            -- Aggregated from agent CTE
            ISNULL(SUM(ast.AgentDeals),   0)                        AS TotalDeals,
            ISNULL(SUM(ast.AgentRevenue), 0)                        AS TotalRevenue,
 
            -- Revenue achievement %
            CASE
                WHEN tl.TargetAmount > 0
                THEN CAST(
                        ISNULL(SUM(ast.AgentRevenue), 0) * 100.0
                        / tl.TargetAmount
                     AS DECIMAL(5,2))
                ELSE NULL
            END                                                      AS RevenueAchievementPct,
 
            -- Units achievement %
            CASE
                WHEN tl.TargetUnits > 0
                THEN CAST(
                        ISNULL(SUM(ast.AgentDeals), 0) * 100.0
                        / tl.TargetUnits
                     AS DECIMAL(5,2))
                ELSE NULL
            END                                                      AS UnitsAchievementPct,
 
            -- Rank among all team leaders by revenue
            RANK() OVER (
                ORDER BY ISNULL(SUM(ast.AgentRevenue), 0) DESC
            )                                                        AS RevenueRank,
            -- Top agent in this team
            tap.TopAgentName,
            tap.TopAgentRevenue,
            tap.TopAgentDeals
 
        FROM TeamLeader tl
        LEFT JOIN SalesAgent      sa  ON sa.TeamLeaderID  = tl.TeamLeaderID
        LEFT JOIN AgentStats      ast ON ast.AgentID      = sa.AgentID
        LEFT JOIN TopAgentPerTeam tap ON tap.TeamLeaderID = tl.TeamLeaderID
                                     AND tap.RowNum = 1
        GROUP BY
            tl.TeamLeaderID, tl.FirstName, tl.LastName,
            tl.Email, tl.Phone, tl.TargetAmount, tl.TargetUnits,
            tap.TopAgentName, tap.TopAgentRevenue, tap.TopAgentDeals
 
        ORDER BY TotalRevenue DESC;
 
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
exec sp_TeamLeaderPerformance @StartDate = '2018-01-01', @EndDate = '2024-12-31', @ProjectID = NULL;

/* ============================================================
   Month-by-month breakdown of deals, revenue, and payments.
   Deal date is sourced from Reservation.ReservationDate
   (Deal has no ContractDate in the ERD — ReservationDate is
   the closest available date stamp in the join chain).
   Payment dates come from Payment.PaidDate.
   Payment links: Payment.PlanID → PaymentPlan.DealID → Deal
   ============================================================ */
CREATE PROCEDURE sp_MonthlyTrend
    @StartDate    DATE = NULL,
    @EndDate      DATE = NULL,
    @ProjectID    INT  = NULL,   -- NULL = all projects
    @AgentID      INT  = NULL,   -- NULL = all agents
    @TeamLeaderID INT  = NULL    -- NULL = all teams
AS
BEGIN
    SET NOCOUNT ON;
 
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());
 
    BEGIN TRY
 
        -- ── Monthly deal & revenue ────────────────────────────────────
        ;WITH MonthlyDeals AS (
            SELECT
                YEAR(res.ReservationDate)                            AS [Year],
                MONTH(res.ReservationDate)                           AS [Month],
                FORMAT(res.ReservationDate, 'yyyy-MM')               AS YearMonth,
                COUNT(DISTINCT d.DealID)                             AS DealsCount,
                ISNULL(SUM(d.TotalAmount),   0)                     AS DealRevenue,
                ISNULL(SUM(d.DownPayment),   0)                     AS DownPaymentsTotal
            FROM Reservation  res
            INNER JOIN Deal     d   ON d.ReservationID  = res.ReservationID
            INNER JOIN Property pr  ON res.PropertyID   = pr.PropertyID
            INNER JOIN SalesAgent sa ON res.AgentID     = sa.AgentID
            LEFT  JOIN TeamLeader tl ON sa.TeamLeaderID = tl.TeamLeaderID
            WHERE res.ReservationDate BETWEEN @StartDate AND @EndDate
              AND (@ProjectID    IS NULL OR pr.ProjectID    = @ProjectID)
              AND (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
              AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)
            GROUP BY
                YEAR(res.ReservationDate),
                MONTH(res.ReservationDate),
                FORMAT(res.ReservationDate, 'yyyy-MM')
        ),
 
        -- ── Monthly installments collected ────────────────────────────
        MonthlyPayments AS (
            SELECT
                FORMAT(pay.PaidDate, 'yyyy-MM')                      AS YearMonth,
                ISNULL(SUM(pay.Amount), 0)                           AS InstallmentsCollected,
                COUNT(pay.PaymentID)                                  AS PaymentsMade
            FROM Payment     pay
            INNER JOIN PaymentPlan pp  ON pay.PlanID        = pp.PlanID
            INNER JOIN Deal        d   ON pp.DealID         = d.DealID
            INNER JOIN Reservation res ON d.ReservationID   = res.ReservationID
            INNER JOIN Property    pr  ON res.PropertyID    = pr.PropertyID
            INNER JOIN SalesAgent  sa  ON res.AgentID       = sa.AgentID
            LEFT  JOIN TeamLeader  tl  ON sa.TeamLeaderID   = tl.TeamLeaderID
            WHERE pay.PaidDate BETWEEN @StartDate AND @EndDate
              AND (@ProjectID    IS NULL OR pr.ProjectID    = @ProjectID)
              AND (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
              AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)
            GROUP BY FORMAT(pay.PaidDate, 'yyyy-MM')
        )
 
        SELECT
            md.[Year],
            md.[Month],
            md.YearMonth,
            DATENAME(MONTH, DATEFROMPARTS(md.[Year], md.[Month], 1)) AS MonthName,
 
            md.DealsCount,
            md.DealRevenue,
            md.DownPaymentsTotal,
 
            ISNULL(mp.InstallmentsCollected, 0)                      AS InstallmentsCollected,
            ISNULL(mp.PaymentsMade,          0)                      AS PaymentsMade,
 
            -- Total cash inflow this month
            md.DownPaymentsTotal
            + ISNULL(mp.InstallmentsCollected, 0)                    AS TotalCashInflow,
 
            -- Month-over-month deal count growth %
            CASE
                WHEN LAG(md.DealsCount) OVER (ORDER BY md.[Year], md.[Month]) > 0
                THEN CAST(
                        (md.DealsCount
                         - LAG(md.DealsCount) OVER (ORDER BY md.[Year], md.[Month])
                        ) * 100.0
                        / LAG(md.DealsCount) OVER (ORDER BY md.[Year], md.[Month])
                     AS DECIMAL(6,2))
                ELSE NULL
            END                                                       AS DealsMoMGrowthPct,
 
            -- Month-over-month revenue growth %
            CASE
                WHEN LAG(md.DealRevenue) OVER (ORDER BY md.[Year], md.[Month]) > 0
                THEN CAST(
                        (md.DealRevenue
                         - LAG(md.DealRevenue) OVER (ORDER BY md.[Year], md.[Month])
                        ) * 100.0
                        / LAG(md.DealRevenue) OVER (ORDER BY md.[Year], md.[Month])
                     AS DECIMAL(6,2))
                ELSE NULL
            END                                                       AS RevenueMoMGrowthPct
 
        FROM MonthlyDeals md
        LEFT JOIN MonthlyPayments mp ON mp.YearMonth = md.YearMonth
 
        ORDER BY md.[Year], md.[Month];
 
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

exec sp_MonthlyTrend @StartDate = '2018-01-01', @EndDate = '2024-12-31', @ProjectID = 1

/* ============================================================
   Tracks Finance Department employee workload.
   This procedure
   therefore reports on deals within the same company as each
   finance employee, grouped by employee, which is the only
   valid join path available in the ERD.
   ============================================================ */
CREATE OR ALTER PROCEDURE sp_FinanceEmployeeActivity
    @StartDate         DATE = NULL,
    @EndDate           DATE = NULL,
    @FinanceEmployeeID INT  = NULL   -- NULL = all finance employees
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());

    BEGIN TRY

        ;WITH CompanyDealStats AS (
            SELECT
                sa.CompanyID,
                COUNT(DISTINCT d.DealID)                             AS TotalDeals,
                ISNULL(SUM(d.TotalAmount),  0)                       AS TotalDealValue,
                ISNULL(SUM(d.DownPayment),  0)                       AS TotalDownPayments,
                COUNT(DISTINCT CASE WHEN d.DealType = 'Cash'         THEN d.DealID END) AS CashDeals,
                COUNT(DISTINCT CASE WHEN d.DealType = 'Installments' THEN d.DealID END) AS InstallmentDeals,
                COUNT(DISTINCT CASE WHEN d.DealType = 'Mortgage'     THEN d.DealID END) AS MortgageDeals
            FROM Deal        d
            INNER JOIN Reservation res ON d.ReservationID  = res.ReservationID
            INNER JOIN SalesAgent  sa  ON res.AgentID      = sa.AgentID
            WHERE res.ReservationDate BETWEEN @StartDate AND @EndDate
            GROUP BY sa.CompanyID
        ),

        CompanyPaymentStats AS (
            SELECT
                sa.CompanyID,
                ISNULL(SUM(pay.Amount), 0)                           AS TotalInstallmentsCollected,
                COUNT(pay.PaymentID)                                  AS PaidInstallmentCount
            FROM Payment     pay
            INNER JOIN PaymentPlan pp  ON pay.PlanID       = pp.PlanID
            INNER JOIN Deal        d   ON pp.DealID        = d.DealID
            INNER JOIN Reservation res ON d.ReservationID  = res.ReservationID
            INNER JOIN SalesAgent  sa  ON res.AgentID      = sa.AgentID
            WHERE pay.PaidDate BETWEEN @StartDate AND @EndDate
            GROUP BY sa.CompanyID
        )

        SELECT
            fd.FinanceID,
            fd.FirstName + ' ' + fd.LastName                        AS FinanceEmployeeName,
            fd.Email,
            fd.Phone,
            fd.HireDate,
            fd.CompanyID,
            c.ManagerFirstName + ' ' + c.ManagerLastName            AS CompanyManager,

            ISNULL(cds.TotalDeals,                 0)               AS CompanyTotalDeals,
            ISNULL(cds.TotalDealValue,             0)               AS CompanyTotalDealValue,
            ISNULL(cds.TotalDownPayments,          0)               AS CompanyDownPayments,
            ISNULL(cds.CashDeals,                  0)               AS CashDeals,
            ISNULL(cds.InstallmentDeals,           0)               AS InstallmentDeals,
            ISNULL(cds.MortgageDeals,              0)               AS MortgageDeals,

            ISNULL(cps.TotalInstallmentsCollected, 0)               AS InstallmentsCollected,
            ISNULL(cps.PaidInstallmentCount,       0)               AS PaidInstallmentCount,

            ISNULL(cds.TotalDownPayments, 0)
            + ISNULL(cps.TotalInstallmentsCollected, 0)             AS TotalCashInflow,

            RANK() OVER (
                ORDER BY ISNULL(cds.TotalDealValue, 0) DESC
            )                                                        AS WorkloadRank

        FROM FinanceDepartment  fd
        INNER JOIN Company          c   ON fd.CompanyID  = c.CompanyID
        LEFT  JOIN CompanyDealStats    cds ON cds.CompanyID = fd.CompanyID
        LEFT  JOIN CompanyPaymentStats cps ON cps.CompanyID = fd.CompanyID

        -- ✅ FIX: removed @CompanyID parameter and filter
        WHERE (@FinanceEmployeeID IS NULL OR fd.FinanceID = @FinanceEmployeeID)

        ORDER BY CompanyTotalDealValue DESC, FinanceEmployeeName;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO


exec sp_FinanceEmployeeActivity @StartDate = '2018-01-01', @EndDate = '2024-12-31', @FinanceEmployeeID = 1;

/* ============================================================
   Lead quality report using available Customer columns:
   CustomerID, AgentID, PreferredType, PreferredLocation,
   FirstName, LastName, Email, Phone, RegistrationDate.
 
   NOTE: No Budget column exists in the ERD, so budget-bracket
   logic is removed. Hot-lead detection is based on whether
   the customer's PreferredType and PreferredLocation match
   any currently available property.
 
   Customer → Agent link  : Customer.AgentID = SalesAgent.AgentID
   Reservation link       : Reservation.AgentID = SalesAgent.AgentID
                            (no direct Customer→Reservation FK in ERD)
   Deal link              : Deal.ReservationID = Reservation.ReservationID
   ============================================================ */

CREATE OR ALTER PROCEDURE sp_CustomerLeadQuality
    @AgentID      INT = NULL,
    @TeamLeaderID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        ;WITH AvailableByPreference AS (
            SELECT
                pr.TypeID,
                pr.LocationID,
                COUNT(pr.PropertyID)  AS AvailableCount,
                MIN(pr.Price)         AS MinAvailablePrice
            FROM Property pr
            WHERE pr.Status = 'Available'
            GROUP BY pr.TypeID, pr.LocationID
        ),

        CustomerActivity AS (
            SELECT
                c.CustomerID,
                c.FirstName + ' ' + c.LastName                      AS CustomerName,
                c.Phone,
                c.Email,
                c.RegistrationDate,
                c.PreferredType,
                c.PreferredLocation,
                c.AgentID,

                -- ✅ FIX: join Reservation on CustomerID (not just AgentID)
                res.ReservationID,
                d.DealID,

                -- Funnel stage
                CASE
                    WHEN d.DealID          IS NOT NULL THEN 'Closed'
                    WHEN res.ReservationID IS NOT NULL THEN 'Reserved'
                    ELSE 'Lead'
                END                                                  AS FunnelStage,

                -- Did the closed deal match preferred type?
                CASE
                    WHEN d.DealID IS NOT NULL
                         AND pr_actual.TypeID = c.PreferredType
                    THEN 1 ELSE 0
                END                                                  AS BoughtPreferredType,

                -- Did the closed deal match preferred location?
                CASE
                    WHEN d.DealID IS NOT NULL
                         AND pr_actual.LocationID = c.PreferredLocation
                    THEN 1 ELSE 0
                END                                                  AS BoughtPreferredLocation,

                pt_actual.TypeName                                   AS ActualBoughtType,
                d.TotalAmount                                        AS ClosedDealAmount,
                d.DealType                                           AS ClosedDealType,

                DATEDIFF(DAY, c.RegistrationDate, GETDATE())        AS LeadAgeDays,

                -- Hot lead: no reservation yet AND matching inventory exists
                CASE
                    WHEN d.DealID          IS NULL
                         AND res.ReservationID IS NULL
                         AND EXISTS (
                             SELECT 1 FROM AvailableByPreference abp
                             WHERE (c.PreferredType     IS NULL OR abp.TypeID     = c.PreferredType)
                               AND (c.PreferredLocation IS NULL OR abp.LocationID = c.PreferredLocation)
                         )
                    THEN 1 ELSE 0
                END                                                  AS IsHotLead

            FROM Customer c
            -- ✅ FIX: Reservation joined on CustomerID
            LEFT JOIN Reservation  res        ON res.CustomerID      = c.CustomerID
            -- Deal from that reservation
            LEFT JOIN Deal         d          ON d.ReservationID     = res.ReservationID
            -- Property that was in the deal
            LEFT JOIN Property     pr_actual  ON res.PropertyID      = pr_actual.PropertyID
            LEFT JOIN PropertyType pt_actual  ON pr_actual.TypeID    = pt_actual.TypeID
            -- Agent filter
            LEFT JOIN SalesAgent   sa         ON c.AgentID           = sa.AgentID
            LEFT JOIN TeamLeader   tl         ON sa.TeamLeaderID     = tl.TeamLeaderID

            WHERE (@AgentID      IS NULL OR sa.AgentID      = @AgentID)
              AND (@TeamLeaderID IS NULL OR tl.TeamLeaderID = @TeamLeaderID)
        )

        SELECT
            ca.CustomerID,
            ca.CustomerName,
            ca.Phone,
            ca.Email,
            ca.RegistrationDate,
            ca.LeadAgeDays,
            ca.PreferredType,
            ca.PreferredLocation,
            ca.FunnelStage,
            ca.IsHotLead,
            ca.ActualBoughtType,
            ca.ClosedDealAmount,
            ca.ClosedDealType,
            ca.BoughtPreferredType,
            ca.BoughtPreferredLocation,
            sa.FirstName + ' ' + sa.LastName                        AS AssignedAgentName,
            sa.Phone                                                 AS AgentPhone,
            tl.FirstName + ' ' + tl.LastName                        AS TeamLeaderName

        FROM CustomerActivity ca
        LEFT JOIN SalesAgent sa ON ca.AgentID      = sa.AgentID
        LEFT JOIN TeamLeader tl ON sa.TeamLeaderID = tl.TeamLeaderID

        ORDER BY
            ca.IsHotLead   DESC,
            ca.FunnelStage ASC,
            ca.LeadAgeDays DESC;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO


exec sp_CustomerLeadQuality  @AgentID = 10; 
/* ============================================================
   Analyses payment plan structures across deals.
   Join chain:
     Payment.PlanID → PaymentPlan.PlanID
     PaymentPlan.DealID → Deal.DealID
     Deal.ReservationID → Reservation.ReservationID
     Reservation.PropertyID → Property.PropertyID
 
   PaymentPlan columns confirmed: PlanID, DealID,
   IntervalMonths, LoanStart (InstallmentCount not visible
   in ERD — omitted to avoid errors).
 
   Payment columns confirmed: PaymentID, PlanID, Amount,
   DueDate, PaidDate, DueSum.
   ============================================================ */
CREATE PROCEDURE sp_InstallmentPlanSummary
    @ProjectID INT  = NULL,  -- NULL = all projects
    @StartDate DATE = NULL,  -- filter by reservation date
    @EndDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
 
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), 1, 1));
    SET @EndDate   = ISNULL(@EndDate,   GETDATE());
 
    BEGIN TRY
 
        -- ── Result Set 1: Deal-type mix and plan statistics ───────────
 
        SELECT
            'DealTypeSummary'                                        AS ReportSection,
            d.DealType,
            COUNT(DISTINCT d.DealID)                                 AS DealCount,
            ISNULL(SUM(d.TotalAmount),  0)                          AS TotalDealValue,
            ISNULL(SUM(d.DownPayment),  0)                          AS TotalDownPayments,
 
            -- Total already paid via installments
            ISNULL(SUM(
                CASE WHEN pay.PaidDate IS NOT NULL
                     THEN pay.Amount ELSE 0 END), 0)                AS TotalCollected,
 
            -- Total still outstanding (DueDate in future, not yet paid)
            ISNULL(SUM(
                CASE WHEN pay.PaidDate IS NULL
                          AND pay.DueDate >= CAST(GETDATE() AS DATE)
                     THEN pay.Amount ELSE 0 END), 0)                AS TotalFutureDue,
 
            -- Overdue: due date passed, not yet paid
            ISNULL(SUM(
                CASE WHEN pay.PaidDate IS NULL
                          AND pay.DueDate < CAST(GETDATE() AS DATE)
                     THEN pay.Amount ELSE 0 END), 0)                AS TotalOverdue,
 
            -- Plan parameters (meaningful for Installments / Mortgage)
            AVG(CAST(pp.IntervalMonths AS FLOAT))                    AS AvgIntervalMonths
 
        FROM Deal        d
        INNER JOIN Reservation  res ON d.ReservationID  = res.ReservationID
        INNER JOIN Property     pr  ON res.PropertyID   = pr.PropertyID
        LEFT  JOIN PaymentPlan  pp  ON pp.DealID        = d.DealID
        LEFT  JOIN Payment      pay ON pay.PlanID       = pp.PlanID
 
        WHERE res.ReservationDate BETWEEN @StartDate AND @EndDate
          AND (@ProjectID IS NULL OR pr.ProjectID = @ProjectID)
 
        GROUP BY d.DealType
        ORDER BY DealCount DESC;
 
 
        -- ── Result Set 2: Projected monthly cash inflow – next 12 months
 
        SELECT
            'MonthlyProjection'                                      AS ReportSection,
            FORMAT(pay.DueDate, 'yyyy-MM')                           AS DueYearMonth,
            YEAR(pay.DueDate)                                        AS DueYear,
            MONTH(pay.DueDate)                                       AS DueMonth,
            DATENAME(MONTH, pay.DueDate)                             AS MonthName,
            COUNT(pay.PaymentID)                                     AS InstallmentsDue,
            ISNULL(SUM(pay.Amount), 0)                              AS ProjectedInflow,
            ISNULL(SUM(
                CASE WHEN pay.PaidDate IS NOT NULL
                     THEN pay.Amount ELSE 0 END), 0)                AS AlreadyPaid,
            ISNULL(SUM(
                CASE WHEN pay.PaidDate IS NULL
                          AND pay.DueDate < CAST(GETDATE() AS DATE)
                     THEN pay.Amount ELSE 0 END), 0)                AS AlreadyOverdue
 
        FROM Payment     pay
        INNER JOIN PaymentPlan  pp  ON pay.PlanID       = pp.PlanID
        INNER JOIN Deal         d   ON pp.DealID        = d.DealID
        INNER JOIN Reservation  res ON d.ReservationID  = res.ReservationID
        INNER JOIN Property     pr  ON res.PropertyID   = pr.PropertyID
 
        WHERE pay.DueDate BETWEEN CAST(GETDATE() AS DATE)
                              AND DATEADD(MONTH, 12, CAST(GETDATE() AS DATE))
          AND (@ProjectID IS NULL OR pr.ProjectID = @ProjectID)
 
        GROUP BY
            FORMAT(pay.DueDate, 'yyyy-MM'),
            YEAR(pay.DueDate),
            MONTH(pay.DueDate),
            DATENAME(MONTH, pay.DueDate)
 
        ORDER BY DueYear, DueMonth;
 
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
EXEC sp_InstallmentPlanSummary @ProjectID = NULL, @StartDate = '2020-11-07', @EndDate = '2024-12-31';

/* ============================================================
   Real-time snapshot of available inventory for sales agents.
   Property features (Parking, HasGarden, HasPool, FloorLevel)
   are confirmed columns on the Property table itself in the ERD.
   PropertyType is a separate table joined via Property.TypeID.
   Location is joined via Property.LocationID.
 
   NOTE: Bedrooms, Bathrooms, ViewType, FinishingType,
   DeliveryType, Furnished are NOT visible on Property in the
   ERD images — they have been removed from this version to
   prevent column-not-found errors. Add them back if your
   actual DDL includes them.
   ============================================================ */
CREATE PROCEDURE sp_PropertyAvailabilitySnapshot
    @ProjectID   INT           = NULL,
    @LocationID  INT           = NULL,
    @TypeID      INT           = NULL,    -- FK to PropertyType
    @MaxPrice    DECIMAL(18,2) = NULL,    -- upper price limit
    @MinPrice    DECIMAL(18,2) = NULL,    -- lower price limit
    @MinSize     DECIMAL(10,2) = NULL,    -- minimum size in m²
    @HasPool     BIT           = NULL,
    @HasGarden   BIT           = NULL,
    @Parking     BIT           = NULL,
    @FloorLevel  INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
 
    BEGIN TRY
 
        SELECT
            pr.PropertyID,
            pr.Title,
            pt.TypeName                                              AS PropertyType,
            pr.Price,
            pr.Size,
            pr.Status,
            pr.Parking,
            pr.HasGarden,
            pr.HasPool,
            pr.FloorLevel,
 
            -- Project details
            p.ProjectID,
            p.ProjectName,
            p.Status                                                 AS ProjectStatus,
 
            -- Location details
            loc.LocationID,
            loc.City,
 
            -- Price per m²
            CASE
                WHEN pr.Size > 0
                THEN CAST(pr.Price / pr.Size AS DECIMAL(10,2))
                ELSE NULL
            END                                                      AS PricePerSqm,
 
            -- How many other available units in the same project/type
            COUNT(pr2.PropertyID) OVER (
                PARTITION BY pr.ProjectID, pr.TypeID
            )                                                        AS SimilarAvailableUnitsInProject
 
        FROM Property pr
        INNER JOIN PropertyType  pt  ON pr.TypeID     = pt.TypeID
        INNER JOIN Project       p   ON pr.ProjectID  = p.ProjectID
        INNER JOIN Location      loc ON pr.LocationID = loc.LocationID
        -- Self-reference for the window count of similar available units
        LEFT  JOIN Property      pr2 ON pr2.ProjectID = pr.ProjectID
                                     AND pr2.TypeID   = pr.TypeID
                                     AND pr2.Status   = 'available'
                                     AND pr2.PropertyID <> pr.PropertyID
 
        WHERE pr.Status = 'available'
          AND (@ProjectID  IS NULL OR pr.ProjectID  = @ProjectID)
          AND (@LocationID IS NULL OR pr.LocationID = @LocationID)
          AND (@TypeID     IS NULL OR pr.TypeID     = @TypeID)
          AND (@MaxPrice   IS NULL OR pr.Price     <= @MaxPrice)
          AND (@MinPrice   IS NULL OR pr.Price     >= @MinPrice)
          AND (@MinSize    IS NULL OR pr.Size      >= @MinSize)
          AND (@HasPool    IS NULL OR pr.HasPool    = @HasPool)
          AND (@HasGarden  IS NULL OR pr.HasGarden  = @HasGarden)
          AND (@Parking    IS NULL OR pr.Parking    = @Parking)
          AND (@FloorLevel IS NULL OR pr.FloorLevel = @FloorLevel)
 
        ORDER BY
            p.ProjectName,
            pt.TypeName,
            pr.Price ASC;
 
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
EXEC sp_PropertyAvailabilitySnapshot @ProjectID = NULL, @LocationID = NULL, @TypeID = NULL, @MaxPrice = 500000, @MinSize = 50, @HasPool = 1;