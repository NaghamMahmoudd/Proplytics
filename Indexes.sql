-- ============================================================
--INDEXES
-- ============================================================
 
   -- Customer → Agent lookup
   CREATE INDEX IX_Customer_AgentID
       ON Customer (AgentID)
       INCLUDE (RegistrationDate, PreferredType, PreferredLocation);
 
   -- Reservation → Agent + Property lookups
   CREATE INDEX IX_Reservation_AgentID
       ON Reservation (AgentID)
       INCLUDE (PropertyID, ReservationDate, ExpiryDate);
 
   CREATE INDEX IX_Reservation_ExpiryDate
       ON Reservation (ExpiryDate)
       INCLUDE (AgentID, PropertyID, ReservationDate);
 
   -- Deal → Reservation
   CREATE INDEX IX_Deal_ReservationID
       ON Deal (ReservationID)
       INCLUDE (TotalAmount, DownPayment, DealType);
 
   -- Payment → Plan + dates
   CREATE INDEX IX_Payment_PlanID_DueDate
       ON Payment (PlanID, DueDate)
       INCLUDE (Amount, PaidDate);
 
   -- PaymentPlan → Deal
   CREATE INDEX IX_PaymentPlan_DealID
       ON PaymentPlan (DealID)
       INCLUDE (IntervalMonths);
 
   -- Property availability snapshot
   CREATE INDEX IX_Property_Status
       ON Property (Status)
       INCLUDE (ProjectID, LocationID, TypeID, Price, Size,
                Parking, HasGarden, HasPool, FloorLevel);
 
   -- SalesAgent → TeamLeader
   CREATE INDEX IX_SalesAgent_TeamLeaderID
       ON SalesAgent (TeamLeaderID)
       INCLUDE (AgentID, CompanyID, AgentTypeID,
                FirstName, LastName, TargetAmount, TargetUnits);
 
   -- FinanceDepartment → Company
   CREATE INDEX IX_FinanceDepartment_CompanyID
       ON FinanceDepartment (CompanyID)
       INCLUDE (FinanceID, FirstName, LastName, Email, Phone);
 
 -- ============================================================
 