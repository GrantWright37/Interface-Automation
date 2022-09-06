/*    ==Scripting Parameters==

    Source Server Version : SQL Server 2016 (13.0.6300)
    Source Database Engine Edition : Microsoft SQL Server Enterprise Edition
    Source Database Engine Type : Standalone SQL Server

    Target Server Version : SQL Server 2016
    Target Database Engine Edition : Microsoft SQL Server Enterprise Edition
    Target Database Engine Type : Standalone SQL Server
*/

USE [automation_R09]
GO

/****** Object:  StoredProcedure [dbo].[PSG_Load_InterfaceMappingLog_PMCodes]    Script Date: 8/17/2022 1:23:18 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

















CREATE PROCEDURE [dbo].[Load_InterfaceMappingLog_PMCodes] @PMList_ID int, @Match_Method int, @Enc_StartDate date, @Enc_EndDate date
AS
BEGIN






/*
Created by: Alex Wright 
Created on: 2022-06-15
Team: PSG Interface team

intent: automatically configure providers that are not already setup to correctly to the provided interface 
paramaters: 
	@Pmlist_Name - the name of the interface as it appears in the pmlist.name field
	@Match_Method - the method by which we determine if a interfaces is configured correctly


Scope: 
	1. Provider associated with an active facility 
	2. Provider is not deleted or part of any 
	2. Associated facility is properly configured to provided provided Pmlist name 
	3. Provider is not properly configured to provided Pmlist name
	4. Provider has an upcoming appointment within the 3 next months or last 3 months (Optional)
	5. All regions in replication

In order to allow for multiple ways of determining when a interface is "properly configured", this proc is designed to run multiple methods which the user will designate upon proc call	 
Note: as of 2022-06-15 there is only one method in use 

 
Method 1 
--------------------------------------------------------------------------------------------------------------------------------------------------------
Facility Configuration Rules (Method 1)
in order to be configured correctly a Facility must pass the following rules 
		A. Edi_Facilities.Code = Edi_Facilities.Hl7id
		B. Entry found in PmCodes when join on Edi_Facilities.ID = Pm_codes.ItemID and the pm_Codes.pmid = ID associated with the provided Pmlist name
		C. PmCodes.External Code equal the Edi_Facilities.Code

Provider Configuration Rules (Method 1)
in order to be configured correctly a Provider must pass the following rules 
		A. Doctor.HL7ID  = Doctor.NPI
		B. Entry found in PmCodes when join on Doctors.Coctorid = Pm_codes.ItemID and the pm_Codes.pmid = ID associated with the provided Pmlist name
		C. PmCodes.External Code equal the Edi_Facilities.Code


Interfaces Using Method 1 
- ADTInMHD

--------------------------------------------------------------------------------------------------------------------------------------------------------

Method 2 - TBD 
--------------------------------------------------------------------------------------------------------------------------------------------------------
Facility Configuration Rules (Method 2)
in order to be configured correctly a Facility must pass the following rules 
		A. TBD
		B. TBD
		C. TBD

Provider Configuration Rules (Method 2)
in order to be configured correctly a Provider must pass the following rules 
		A. TBD
		B. TBD
		C. TBD

Interfaces Using Method 2
- TBD

--------------------------------------------------------------------------------------------------------------------------------------------------------


--  Table of contents 

Section 0: Error handeling and #FinalResults temp table DDL
Section 1: Start of Match Method 1 
			1.1 Load Facilities temp table #Facilities_M1
			1.2 Load Facilities temp table #Providers_M1
			1.3 load #Prov_with_Upcoming_Appt_M1
Section 2: Start of Match Method 2 
	Note: as of 6/15/2022 there are no other match methods defined so this section is just error handaling and sections 2.1 - 2.3 are just to illustrate thre structure 
			2.1 Load Facilities temp table #Facilities_M2
			2.2 Load Facilities temp table #Providers_M2
			2.3 load #Prov_with_Upcoming_Appt_M2
Section X : Interface Specific Updates/filtering
			x.1 ADTInMHD Specifc Changes


Final Section: Insert into  [automation_R09].[dbo].[InterfaceMapping_Log]

*/


begin -- Main Wrapper

 SET XACT_ABORT  ON;

--/////////////// Section 0 Error handeling to check @Pmlist_Name provided  ////////////////////////////////////////////////////////////////////////////////////////////////////
-- Error Handeling to see if @Pmlist_Name is valid 



begin


if (@PMList_ID is null or ltrim(rtrim(@PMList_ID)) = '')
begin
 raiserror('No @PMList_ID provided. No Records Loaded.', 16, 1) 
 return 
end 


if (@Enc_StartDate is null or @Enc_StartDate > cast (getdate() as date))
begin
 raiserror('Invalid Encounter StartDate parameter supplied. No Records Loaded. ', 16, 1) 
 return 
end 



if (@Enc_StartDate is null)
begin
 raiserror('Invalid Encounter EndDate parameter supplied. No Records Loaded. ', 16, 1) 
 return 
end 

Declare @Does_Pmlist_Exist int
set @Does_Pmlist_Exist  =
(
Select top 1 id
from mobiledoc_R09.dbo.pmlist with (nolock)
where 1=1 
and id = @PMList_ID
and deleteFlag = 0

)



if (@Does_Pmlist_Exist is null )

begin 
 raiserror('The Parameter @PMList_ID provided was not found in Pmlist table or has been deleted. No Records Loaded.', 16, -1) 
 return
end 

-- Create temp tables for results


-- Create temp table to load results into 
-- all Methods should load into this same temp table in order to reduce redundancy

CREATE TABLE #FinalResults(
	[ECW_Facilityid] [int] NOT NULL,			           -- a FK linking back to edi_Facilities.ID
	[Facility_Code] [varchar](10) NOT NULL,                -- the text value that you would like have entered as the EDI_Facilities.Code. 
	[Ecw_Doctorid] [int] NOT NULL,				           -- a FK linking back to Doctors.ID
	[PMCodes_EcwCode] [varchar](30) NULL,                  -- the text value that you would like have entered as Pm_Codes.ECWCode
	[PMCodes_ExternalCode] [varchar](30) NULL,             -- the text value that you would like have entered as Pm_Codes.ExternalCode
	[Doctors_Hl7id] [varchar](30) NULL,			           -- the text value that you would like have entered as Doctors.Hl7ID
	[Provider_Speciality] [varchar](60) NOT NULL,          -- The provider's specialty
	[PMList_Id] [int] NOT NULL,		           -- the ID value of the PMList table
	[Has_Existing_Configuration] [int] NOT NULL,  -- Flag indicating if there is an existing PM_Codes entry linking thr provider and provided interface, 1= yes, 0 = No
	[Pmcodes_ID] [int] NULL								   -- the PK of the PM Codes table. will only be populated if [Has_Existing_Configuration] = 1
) ON [PRIMARY]




end

-- Logic Gate to determine witch match method to use 
  if (@Match_Method = 1)
--/////////////// Section 1 Begin Match Method 1 ////////////////////////////////////////////////////////////////////////////////////////////////////
begin 


-- //////////////// Section 1.1  Load Facilities temp table #Facilities_M1 ////////////////////////////////////////////////////////////////////////////////////////
-- create a temp table containing active facilities and determine if they are properly configured for the provided interface 

begin



Select 
distinct
fac.Id, 
fac.name, 
fac.code as Facility_Code, 
fac.pos, 
case 
when ltrim(rtrim(hl7id)) = '' then null 
else hl7id 
end as hl7id,
case
when ltrim(rtrim( pmc.externalCode )) = '' then null 
else   pmc.externalCode
end as ExternalCode,
case 
when POS = 11 and fac.code = pmc.externalCode and fac.code = fac.hl7id then 1 
else 0
end as Is_Configured_Correctly, 
pmc.Pmcodes_id as Pmcodes_id ,
@PMList_ID as PMList_Id
into #Facilities_M1
from mobiledoc_R09.dbo.edi_facilities as fac with (nolock)
  join 
  (
select  eCWCode, externalCode, pc.Id as Pmcodes_id , pc.PMId , itemid,
-- since there are a handful of duplicates, need to filter down to one row by defaulting to the latest ID created
ROW_NUMBER () over (partition by  itemid order by ID desc ) as Is_Latest 
from mobiledoc_R09.dbo.pmcodes pc with (nolock)
where 1=1 
and pc.pmid = @PMList_ID
and pc.flag = 'F'



) as pmc on (pmc.itemid = fac.Id  and fac.pos = 11 and pmc.Is_Latest = 1 )
where 1=1 
and POS = 11 -- office
and fac.DeleteFlag = 0
and fac.code not like 'zz%'


end


-- //////////////// Section 1.2  Load Facilities temp table #Providers_M1////////////////////////////////////////////////////////////////////////////////////////
-- -- create a temp table containing active Providers and determine if they are properly configured for the provided interface 
begin 

select distinct 
dr.doctorID, 
dr.FacilityId, 
dr.Provider_LastName, 
dr.Provider_FirstName,
npi, 
Provider_Speciality,
eCWCode,
case 
when ltrim(rtrim(hl7id)) = '' then null 
else hl7id 
end as hl7id,
case
when ltrim(rtrim(externalCode )) = '' then null 
else  externalcode
end as ExternalCode,

case when pmc.eCWCode is not null 
then 1 else 0
end as Has_Existing_Configuration,
Pmcodes_ID,
PMID, 

case 
when  pmc.externalCode = dr.hl7id 
and pmc.externalCode = dr.npi 
and ltrim(rtrim(dr.NPI)) <> ''
and dr.NPI not like '9999999%'
and dr.NPI not like '0000000%'
then 1 
else 0
end as Is_Configured_Correctly
into #Providers_M1
from 
(
Select  
doctorID, 
FacilityId, 
u.ulname as Provider_LastName, 
u.ufname as Provider_FirstName, 
hl7id, 
NPI,
d.speciality as Provider_Speciality
from mobiledoc_R09.dbo.doctors as d with (nolock)
join mobiledoc_R09.dbo.users as u  with (nolock) on (d.doctorID = u.uid )
where 1=1
and u.ulname not like 'zz%'
and u.status = 0
and u.UserType = 1
and u.delFlag = 0
and FacilityId <> 0 -- provider is associated with a facility
and d.NPI is not null -- NPI is not null
and ltrim(rtrim(d.NPI)) <> '' -- NPI is not empty spaces
and len (NPI) = 10 -- NPi is right length 
and d.doctorid not in
	(
	select userid
from mobiledoc_R09.dbo.grouppermissions with (nolock)
where Groupid = 58-- user groups to exclude
and userid is not null
	)
) as dr
left join 
(
select   eCWCode, externalCode, Id as Pmcodes_ID, pmid,  itemid,  
-- since there are a handful of duplicates, need to filter down to one row by defaulting to the latest ID created
ROW_NUMBER () over (partition by itemid order by ID desc ) as Is_Latest 
from mobiledoc_R09.dbo.pmcodes pc with (nolock)
where pc.pmid = @PMList_ID
and pc.flag = 'D'

) as pmc on ( pmc.itemId= dr.doctorID and pmc.Is_Latest = 1) 
where 1=1



end


-- //////////////// Section 1.3 load #Prov_with_Upcoming_Appt_M1////////////////////////////////////////////////////////////////////////////////////////
-- limit the scope by restricting to providers who have appointments at the facility in question within a certain date range

begin
select  doctorID, facilityId, cast (min (date) as date) as Next_Appt
into #Prov_with_Upcoming_Appt_M1
from  mobiledoc_R09.dbo.enc with (nolock)
where 1=1
and enc.encType = 1
and enc.deleteFlag = 0
AND status != 'CANC'
and cast (date as date ) >= @Enc_StartDate -- appointments as soon as 3 months back
and cast (date as date ) <= @Enc_EndDate -- apointments as late as 3 month from now 
group  by doctorID, facilityId

end



-- //////////////// Section 1.4 Insert into #FinalResults for Method 1////////////////////////////////////////////////////////////////////////////////////////
-- using the temp tables created in sections 1.1 - 1.3, we will join those tables together to load the #FinalResults  temp table
begin

insert into #FinalResults

Select distinct
p.FacilityId as ECW_Facilityid, 
f.Facility_Code, 
p.doctorID as Ecw_Doctorid, 
Ltrim(Rtrim(p.Npi))  as PMCodes_EcwCode, 
Ltrim(Rtrim(p.Npi))  as PMCodes_ExternalCode, 
cast (Ltrim(Rtrim(Npi)) as varchar (30) )  as Doctors_Hl7id,
p.Provider_Speciality, 
f.PMList_Id, 
p.Has_Existing_Configuration, 
p.Pmcodes_ID
from #Providers_M1 as p
join #Prov_with_Upcoming_Appt_M1 as  apt on (  apt.doctorID = p.doctorID and apt.facilityId = p.FacilityId  )
join #Facilities_M1 as f on (f.id = p.FacilityId and f.Is_Configured_Correctly = 1 )
where 1=1
and p.Is_Configured_Correctly = 0





end


end


--/////////////// Section 2  Begin Match Method 2 ////////////////////////////////////////////////////////////////////////////////////////////////////
-- If the match method provided is not 1, then we will run this portion of the code
-- As of 6/15/2022 there is only one match method, so this section will just contain an error statment letting the user know they need to select another match method
else if (@Match_Method <> 1 or @Match_Method is null)

begin 

raiserror('Unsupported Match Method. No Records Loaded.', 16, -1) 
return
end 


--////////////// Section X: Interface Specifc Changes /////////////////////////////////////////
-- make changes to the FinalResults table based on interfaces specific business rules 
-- while the rest of the sections are designed to be interface agnostic, this section is reserved for interface specifc changes
-- Note: if in the future you need to filter on a field not found in the #FinalResults table, you will simply need to add that column to the temp table 
begin



-- need to get the PM names 
declare @Pmlist_Name varchar (50)
set  @Pmlist_Name = 
(
select top 1 name
from mobiledoc_R09.dbo.pmlist pc with (nolock)
where 1=1 
and id = @PMList_ID


)

--////////////// Section X.1: ADTInMHD Specifc Changes /////////////////////////////////////////
if (@Pmlist_Name = 'ADTInMHD')

begin 


delete 
from #FinalResults
where Provider_Speciality in 
(
'Dietician', 
'Emergency Medicine', 
'HOSPITALIST', 
'Pharm D', 
'Radiology', 
'Social Worker - Clinical'
)

end 


end 


--/////////////// Final Section: Insert into  [eCWStage].[dbo].[InterfaceMapping_Log] ////////////////////////////////////////////////////////////////////////////////////////////////////
-- Write Inserts/updates to #Pre_Merge_Results and then perform merge against [eCWStage].[dbo].[InterfaceMapping_Log]


begin
-- write to team loging table

Select 
'PmCodes' as Mapping_Type, 
'Insert' as Action_Type,
Ecw_Doctorid as DoctorID,
ECW_Facilityid as EDI_Facilities_ID, 
PMList_Id as PMList_ID,
pmcodes_id as PMCodes_ID,
PMCodes_EcwCode,
PMCodes_ExternalCode,
'D' as PMcodes_Flag,
null as LabList_ID, 
null as LabCodes_ID,
null as LabCodes_Code,
null as LabCodes_Flag,
Doctors_Hl7id, 
null as Edi_Facilities_HL7id,
0 as Is_Implemented,
null as Last_Encounter_Date,
getutcdate () as CreatedDate_UTC, 
null as ModifiedDate_UTC
into #Pre_Merge_Results
from #FinalResults
where 1=1 
and Has_Existing_Configuration = 0
and Pmcodes_ID is  null -- if there is no Pmcodes_id already in existence then we will need to insert a new one 

union all

-- now if there are any to update insert them into the mapping log table with a action type of 'U' for update

Select
'PmCodes' as Mapping_Type, 
'Update' as Action_Type,
Ecw_Doctorid as DoctorID,
ECW_Facilityid as EDI_Facilities_ID, 
PMList_Id as PMList_ID,
pmcodes_id as PMCodes_ID,
PMCodes_EcwCode,
PMCodes_EcwCode,
'D' as PMcodes_Flag,
null as LabList_ID, 
null as LabCodes_ID,
null as LabCodes_Code,
null as LabCodes_Flag,
Doctors_Hl7id, 
null as Edi_Facilities_HL7id,
0 as Is_Implemented,
null as Last_Encounter_Date,
getutcdate () as CreatedDate_UTC, 
null as ModifiedDate_UTC
from #FinalResults
where 1=1 
and Has_Existing_Configuration = 1
and Pmcodes_ID is not null



-- in the event that we this proc runs before the latest changes have been implemented, but the providers info has changed, we want to update the existing record set to be implemented with the latest info

  MERGE [automation_R09].[dbo].[InterfaceMappingLog] AS Target
    USING #Pre_Merge_Results	AS Source
    ON  source.DoctorID = Target.DoctorID 
    and source.PMList_ID = Target.PMList_ID 
	and Source.Is_Implemented = target.Is_Implemented  -- including this in join condition because the source.is_implemented will always be 0, and we only want to update records that have not yet been implemented 
	and source.Mapping_Type = Target.Mapping_Type
    -- For Inserts
    WHEN NOT MATCHED BY Target THEN
        INSERT (Mapping_Type,Action_Type,	DoctorID,EDI_Facilities_ID,	PMList_ID,	PMCodes_ID,	PMCodes_EcwCode,	PMCodes_ExternalCode,	PMcodes_Flag,	LabList_ID,	LabCodes_ID,	LabCodes_Code,	LabCodes_Flag,	Doctors_Hl7id,	Edi_Facilities_HL7id,	Is_Implemented, Last_Encounter_Date	,CreatedDate_UTC,ModifiedDate_UTC) 
        VALUES (Source.Mapping_Type,Source.Action_Type,Source.DoctorID,Source.EDI_Facilities_ID,Source.PMList_ID,	Source.PMCodes_ID,	Source.PMCodes_EcwCode,	Source.PMCodes_ExternalCode,	Source.PMcodes_Flag,	Source.LabList_ID,	Source.LabCodes_ID,	Source.LabCodes_Code,	Source.LabCodes_Flag,	Source.Doctors_Hl7id,	Source.Edi_Facilities_HL7id,	Source.Is_Implemented, source.Last_Encounter_Date,	Source.CreatedDate_UTC,Source.ModifiedDate_UTC)
    
    -- For Updates
    WHEN MATCHED THEN UPDATE SET
        Target.EDI_Facilities_ID	= Source.EDI_Facilities_ID,
        Target.PMCodes_EcwCode		= Source.PMCodes_EcwCode,
		Target.PMCodes_ExternalCode	= Source.PMCodes_ExternalCode,
        Target.Action_Type		    = Source.Action_Type,
		target.PMCodes_ID           = Source.PMCodes_ID,
		Target.Doctors_Hl7id		= Source.Doctors_Hl7id;


--truncate table [eCWStage].[dbo].[InterfaceMapping_Log]


end


end



end
GO
