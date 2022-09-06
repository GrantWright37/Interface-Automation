/*    ==Scripting Parameters==

    Source Server Version : SQL Server 2016 (13.0.6300)
    Source Database Engine Edition : Microsoft SQL Server Enterprise Edition
    Source Database Engine Type : Standalone SQL Server

    Target Server Version : SQL Server 2016
    Target Database Engine Edition : Microsoft SQL Server Enterprise Edition
    Target Database Engine Type : Standalone SQL Server
*/

USE [Automation_R09]
GO

/****** Object:  Table [dbo].[InterfaceMappingLog]    Script Date: 8/17/2022 1:17:25 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[InterfaceMappingLog](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[Mapping_Type] [varchar](50) NULL,
	[Action_Type] [varchar](50) NULL,
	[DoctorID] [int] NULL,
	[EDI_Facilities_ID] [int] NULL,
	[PMList_ID] [int] NULL,
	[PMCODES_ID] [int] NULL,
	[PMCodes_EcwCode] [varchar](120) NULL,
	[PMCodes_ExternalCode] [varchar](120) NULL,
	[PMCodes_Flag] [varchar](5) NULL,
	[LabList_ID] [int] NULL,
	[LabCodes_ID] [int] NULL,
	[LabCodes_Code] [varchar](60) NULL,
	[LabCodes_Flag] [varchar](5) NULL,
	[Doctors_HL7ID] [varchar](30) NULL,
	[Edi_Facilities_Hl7id] [varchar](30) NULL,
	[Is_Implemented] [int] NOT NULL,
	Last_encounter_Date [datetime] null,
	[CreatedDate_UTC] [datetime] NOT NULL,
	[ModifiedDate_UTC] [datetime] NULL
) ON [PRIMARY]
GO


