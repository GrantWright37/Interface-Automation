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

/****** Object:  StoredProcedure [dbo].[PSG_Load_InterfaceMappingLog_Master]    Script Date: 8/17/2022 2:02:13 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO












CREATE PROCEDURE [dbo].[PSG_Load_InterfaceMappingLog_Master] 
AS
BEGIn

/*
Created by: Alex Wright 
Created on: 2022-06-22
Team: PSG Interface team

intent: this is the master loading proc which will be used to call the related PM and Lab loading procs for all labs/Pms that we want to automate

*/



--- populate the labs temp table 
begin
-- Labcorp 
Select 
 id, 
 1 as MatchMethod, 
 cast (DATEADD(month, -1, getdate()) as date ) as Enc_Start_Range, 
cast (DATEADD(month, 1, getdate()) as date ) as Enc_End_Range, 
 ROW_NUMBER () over ( order by  id ) as RowNumber
into #Labs
from  MobileDoc_R02.dbo.lablist with (nolock)
where 1=1
and deleteFlag = 0
and name like 'R%labcorp_OG%'

end


-- populate the #Pm temp table 

begin 


-- MHD 
Select  
 id,
  1 as MatchMethod, 
cast (DATEADD(month, -1, getdate()) as date ) as Enc_Start_Range, 
cast (DATEADD(month, 1, getdate()) as date ) as Enc_End_Range, 
  ROW_NUMBER () over ( order by id ) as RowNumber
--into #Pm
from  MobileDoc_R02.dbo.pmlist 
where 1=1
and deleteFlag = 0
and name = 'ADTInMHD'


end




-- Lab Variables
declare @Lab_mathchMethod int 
declare @Lab_Region_ID int
declare @Lab_LabList_ID int
declare @Lab_enc_Start date 
declare @Lab_enc_end date 


-- Pm variables 


declare @PM_mathchMethod int 
declare @PM_Pmlist_ID int
declare @PM_enc_Start date 
declare @PM_enc_end date 

Select 
@PM_Pmlist_ID = id,
@PM_mathchMethod = MatchMethod
from #Pm
where ROWNUMBER = 1


-- loop Variables 

Declare @Lab_Loop_Limit int
Set @Lab_Loop_Limit = (select max (ROWNUMBER) from #Labs)

declare @Lab_Loop_Count int 
set @Lab_Loop_Count = 1


Declare @PM_Loop_Limit int
Set @PM_Loop_Limit = (select max (ROWNUMBER) from #Pm)

declare @PM_Loop_Count int 
set @PM_Loop_Count = 1




-- Lab loop 
 while (@Lab_Loop_Count <= @Lab_Loop_Limit)

 begin 

 Select 
@Lab_LabList_ID = id,
@Lab_mathchMethod = MatchMethod,
@Lab_enc_Start = Enc_Start_Range,
@Lab_enc_end = Enc_End_Range
from #Labs
where ROWNUMBER = @Lab_Loop_Count


-- call proc to load labcodes 

EXEC [Automation_R09].[dbo].[Load_InterfaceMappingLog_LabCodes]
		@LabList_ID = @Lab_LabList_ID,
		@Match_Method = @Lab_mathchMethod,
		@Enc_StartDate = @Lab_enc_Start,
		@Enc_EndDate = @Lab_enc_end;

-- itterate to next row before starting loop again 
Set @Lab_Loop_Count = @Lab_Loop_Count + 1

 end 



 -- PM loop 
 while (@pm_Loop_Count <= @pm_Loop_Limit)

 begin 

 Select 
@pm_PMList_ID = id,
@pm_mathchMethod = MatchMethod,
@pm_enc_Start = Enc_Start_Range,
@pm_enc_end = Enc_End_Range
from #pm
where ROWNUMBER = @PM_Loop_Count


-- call proc to load labcodes 

EXEC [Automation_R09].[dbo].[Load_InterfaceMappingLog_PMCodes]
		@PMList_ID = @pm_PMList_ID,
		@Match_Method = @pm_mathchMethod,
		@Enc_StartDate = @PM_enc_Start,
		@Enc_EndDate = @PM_enc_end;

-- itterate to next row before starting loop again 
Set @PM_Loop_Count = @PM_Loop_Count + 1

 end 



 end

GO


