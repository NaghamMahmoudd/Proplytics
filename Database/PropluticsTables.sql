CREATE TABLE AgentType (
    AgentTypeID   INT          PRIMARY KEY,
    CommissionRate DECIMAL(5,2) NOT NULL,
    AgentTypeName  VARCHAR(100) NOT NULL
);

CREATE TABLE Location (
    LocationID          INT         PRIMARY KEY,
    City                VARCHAR(100) NOT NULL,
    District            VARCHAR(100) NOT NULL,
    --AvgPricePerMeter    DECIMAL(12,2) 
);

CREATE TABLE Company (
    CompanyID          INT           PRIMARY KEY,
    ManagerID          INT,
    ManagerFirstName   VARCHAR(100),
    ManagerLastName    VARCHAR(100),
    ManagerEmail       VARCHAR(150),
    ManagerPhone       VARCHAR(20),
    Role               VARCHAR(100),
    Password           VARCHAR(255)  NOT NULL,
    Username           VARCHAR(100)  NOT NULL UNIQUE,
    YearsOfExperience  INT,
    ManagerHireDate    DATE,
    CompanyPhone       VARCHAR(20),
    CompanyEmail       VARCHAR(150),
    CompanyName        VARCHAR(200)  NOT NULL
);

CREATE TABLE PropertyType (
    TypeID   INT          PRIMARY KEY,
    TypeName VARCHAR(100) NOT NULL
);


CREATE TABLE Project (
    ProjectID    INT          PRIMARY KEY,
    CompanyID    INT          NOT NULL,
    LocationID   INT          NOT NULL,
    ProjectName  VARCHAR(200) NOT NULL,
    Description  TEXT,
    StartDate    DATE,
    EndDate      DATE,
    TotalUnits   INT,
    Status       VARCHAR(50),
    CONSTRAINT fk_project_company  FOREIGN KEY (CompanyID)  REFERENCES Company(CompanyID),
    CONSTRAINT fk_project_location FOREIGN KEY (LocationID) REFERENCES Location(LocationID)
);

CREATE TABLE Property (
    PropertyID    INT            PRIMARY KEY,
    ProjectID     INT            NOT NULL,
    LocationID    INT            NOT NULL,
    TypeID        INT            NOT NULL,
    Title         VARCHAR(200)   NOT NULL,
    Price         DECIMAL(14,2)  NOT NULL,
    Size          DECIMAL(10,2),
    Status        VARCHAR(50),
    Parking       BIT,
    HasGarden     BIT,
    Furnished     BIT,
    HasPool       BIT,
    FloorLevel    INT,
    ViewType      VARCHAR(100),
    DeliveryType  VARCHAR(100),
    Bedrooms      INT,
    DeliveryDate  DATE,
    FinishingType VARCHAR(100),
    Bathrooms     INT,
    CONSTRAINT fk_property_project  FOREIGN KEY (ProjectID)  REFERENCES Project(ProjectID),
    CONSTRAINT fk_property_location FOREIGN KEY (LocationID) REFERENCES Location(LocationID),
    CONSTRAINT fk_property_type     FOREIGN KEY (TypeID)     REFERENCES PropertyType(TypeID)
);

CREATE TABLE TeamLeader (
    TeamLeaderID      INT          PRIMARY KEY,
    CompanyID         INT          NOT NULL,
    FirstName         VARCHAR(100) NOT NULL,
    LastName          VARCHAR(100) NOT NULL,
    Email             VARCHAR(150) UNIQUE,
    Phone             VARCHAR(20),
    HireDate          DATE,
    TargetAmount      DECIMAL(14,2),
    TargetUnits       INT,
    YearsOfExperience INT,
    Username          VARCHAR(100) NOT NULL UNIQUE,
    Password          VARCHAR(255) NOT NULL,
    Role              VARCHAR(100),
    CONSTRAINT fk_teamleader_company FOREIGN KEY (CompanyID) REFERENCES Company(CompanyID)
);


CREATE TABLE FinanceDepartment (
    FinanceID  INT          PRIMARY KEY,
    CompanyID  INT          NOT NULL,
    FirstName  VARCHAR(100) NOT NULL,
    LastName   VARCHAR(100) NOT NULL,
    Email      VARCHAR(150) UNIQUE,
    Phone      VARCHAR(20),
    HireDate   DATE,
    Username   VARCHAR(100) NOT NULL UNIQUE,
    Password   VARCHAR(255) NOT NULL,
    Role       VARCHAR(100),
    CONSTRAINT fk_finance_company FOREIGN KEY (CompanyID) REFERENCES Company(CompanyID)
);

CREATE TABLE SalesAgent (
    AgentID           INT          PRIMARY KEY,
    TeamLeaderID      INT,
    CompanyID         INT          NOT NULL,
    AgentTypeID       INT          NOT NULL,
    FirstName         VARCHAR(100) NOT NULL,
    LastName          VARCHAR(100) NOT NULL,
    Email             VARCHAR(150) UNIQUE,
    Phone             VARCHAR(20),
    HireDate          DATE,
    TargetUnits       INT,
    TargetAmount      DECIMAL(14,2),
    YearsOfExperience INT,
    Username          VARCHAR(100) NOT NULL UNIQUE,
    Password          VARCHAR(255) NOT NULL,
    Role              VARCHAR(100),
    CONSTRAINT fk_agent_teamleader FOREIGN KEY (TeamLeaderID) REFERENCES TeamLeader(TeamLeaderID),
    CONSTRAINT fk_agent_company    FOREIGN KEY (CompanyID)    REFERENCES Company(CompanyID),
    CONSTRAINT fk_agent_agenttype  FOREIGN KEY (AgentTypeID)  REFERENCES AgentType(AgentTypeID)
);

CREATE TABLE Customer (
    CustomerID        INT          PRIMARY KEY,
    AgentID           INT,
    PreferredType     INT,
    PreferredLocation INT,
    FirstName         VARCHAR(100) NOT NULL,
    LastName          VARCHAR(100) NOT NULL,
    Email             VARCHAR(150) UNIQUE,
    Phone             VARCHAR(20),
    RegistrationDate  DATE,
    Budget            DECIMAL(14,2),
    Role              VARCHAR(100),
    Password          VARCHAR(255),
    Username          VARCHAR(100) UNIQUE,
    CONSTRAINT fk_customer_agent    FOREIGN KEY (AgentID)           REFERENCES SalesAgent(AgentID),
    CONSTRAINT fk_customer_type     FOREIGN KEY (PreferredType)     REFERENCES PropertyType(TypeID),
    CONSTRAINT fk_customer_location FOREIGN KEY (PreferredLocation) REFERENCES Location(LocationID)
);


CREATE TABLE Reservation (
    ReservationID   INT           PRIMARY KEY,
    CustomerID      INT           NOT NULL,
    AgentID         INT           NOT NULL,
    PropertyID      INT           NOT NULL,
    ReservationDate DATE          NOT NULL,
    ExpiryDate      DATE,  -- Calculated field
    DepositAmount   DECIMAL(14,2),
    DepositStatus   VARCHAR(50),
    Status          VARCHAR(50),
    CONSTRAINT fk_reservation_customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT fk_reservation_agent    FOREIGN KEY (AgentID)    REFERENCES SalesAgent(AgentID),
    CONSTRAINT fk_reservation_property FOREIGN KEY (PropertyID) REFERENCES Property(PropertyID)
);


CREATE TABLE Deal (
    DealID        INT           PRIMARY KEY,
    ReservationID INT           NOT NULL UNIQUE,  -- 1-to-1 with Reservation
    FinanceID     INT,
    TotalAmount   DECIMAL(14,2) NOT NULL,
    DownPayment   DECIMAL(14,2),
    DealType      VARCHAR(100),
    ContractType  VARCHAR(100),
    ContractDate  DATE,
    Status        VARCHAR(50),
    CONSTRAINT fk_deal_reservation FOREIGN KEY (ReservationID) REFERENCES Reservation(ReservationID),
    CONSTRAINT fk_deal_finance     FOREIGN KEY (FinanceID)     REFERENCES FinanceDepartment(FinanceID)
);



CREATE TABLE PaymentPlan (
    PlanID           INT           PRIMARY KEY,
    DealID           INT           NOT NULL,
    InterestRate     DECIMAL(5,2),
    PlanStartDate    DATE,
    InstallmentCount INT,
    IntervalMonths   INT,
    CONSTRAINT fk_paymentplan_deal FOREIGN KEY (DealID) REFERENCES Deal(DealID)
);


CREATE TABLE Payment (
    PaymentID         INT           PRIMARY KEY,
    DealID            INT           NOT NULL,
    PlanID            INT,
    Amount            DECIMAL(14,2) NOT NULL,
    PaidDate          DATE,
    DueDate           DATE,
    Status            VARCHAR(50),
    InstallmentNumber INT,
    PaymentMethod     VARCHAR(100),
    CONSTRAINT fk_payment_deal FOREIGN KEY (DealID) REFERENCES Deal(DealID),
    CONSTRAINT fk_payment_plan FOREIGN KEY (PlanID) REFERENCES PaymentPlan(PlanID)
);

