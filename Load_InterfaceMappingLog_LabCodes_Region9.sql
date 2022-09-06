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

/****** Object:  StoredProcedure [dbo].[PSG_Load_InterfaceMappingLog_LabCodes]    Script Date: 8/17/2022 1:52:14 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

















CREATE PROCEDURE [dbo].[Load_InterfaceMappingLog_LabCodes]  @LabList_ID int, @Match_Method int, @Enc_StartDate date, @Enc_EndDate date
AS
BEGIN






/*
Created by: Alex Wright 
Created on: 2022-06-15
Team: PSG Interface team

intent: automatically configure labcodes for providers that are not already setup are not already setup but have are associated with a facility that is has been configured to recieve the labs and they have an upcoming appointmne at that faciility in the date range provided
paramaters: 
	@LabList - the labid of the interface as it appears lablist.id
	@Match_Method - the method by which we determine if a interfaces is configured correctly
	@Enc_StartDate  the first date that in the encounter date range 
	@Enc_EndDate - the last  date that in the encounter date range 

Scope: 
	1. Provider associated with an active facility 
	2. Provider is not deleted or part of any excluded user permission groups
	2. Associated facility is has an entyry in the labcodes table for the @LabList_ID provided
	3. Provider is not properly configured in the labCodes table for the @LabList_ID provided
	4. Provider has an upcoming appointment within Date range provided between @Enc_StartDate and  @Enc_EndDate


In order to allow for multiple ways of determining when a interface is "properly configured", this proc is designed to run multiple methods which the user will designate upon proc call	 
Note: as of 2022-06-15 there is only one method in use 

 
Method 1 
--------------------------------------------------------------------------------------------------------------------------------------------------------
Facility Configuration Rules (Method 1)
in order to be configured correctly a Facility must pass the following rules 
A. Entry found in Labcodes when join on Edi_Facilities.ID = Lab_codes.ItemID and the Labcodes_Codes.labid = @LabList_ID

-- not sure if these are needed. currenlty not part of logic, but the PM codes has somethiong similar
		B. Edi_Facilities.Code = Edi_Facilities.Hl7id  ??? is this needed 
		C. Labcode.Code = labinterfaceinfo.CustomerId ???  -- 


		

Provider Configuration Rules (Method 1)
in order to be configured correctly a Provider must pass the following rules 
		A. Entry found in labcodes when join on Doctors.doctorid = Pm_codes.ItemID and the labcodes_Codes.labid = @LabList_ID
		B. labcodes.code Code equal the Doctors.NPI


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


Final Section: Insert into  [Automation_R09].[dbo].[InterfaceMapping_Log]

*/


begin -- Main Wrapper

 SET XACT_ABORT  ON;

--/////////////// Section 0 Error handeling to check @Lab_Name provided  ////////////////////////////////////////////////////////////////////////////////////////////////////
-- Error Handeling to see if @Lab_Name is valid 



begin


if (@LabList_ID is null or ltrim(rtrim(@LabList_ID)) = '')
begin
 raiserror('No @LabList_ID provided. No Records Loaded.', 16, 1) 
 return 
end 


Declare @Does_Lablist_Exist int
set @Does_Lablist_Exist  =
(
Select top 1 id
from mobiledoc_R09.dbo.lablist with (nolock)
where 1=1 
and id = @LabList_ID
and deleteFlag = 0

)



if (@Does_Lablist_Exist is null )

begin 
 raiserror('The Parameter @LabList_ID provided was not found in LabList table or has been deleted. No Records Loaded.', 16, -1) 
 return
end 

-- Create temp tables for results


-- Create temp table to load results into 
-- all Methods should load into this same temp table in order to reduce redundancy

CREATE TABLE #FinalResults(

	[ECW_Facilityid] [int] NOT NULL,			           -- a FK linking back to edi_Facilities.ID
	[Facility_Code] [varchar](10) NOT NULL,                -- the text value that you would like have entered as the EDI_Facilities.Code. 
	[Ecw_Doctorid] [int] NOT NULL,				           -- a FK linking back to Doctors.ID
	[LabCodes_Code] [varchar](30) NULL,                  -- the text value that you would like have entered as Labcodes.Code
	[Doctors_Hl7id] [varchar](30) NULL,			           -- the text value that you would like have entered as Doctors.Hl7ID
	[Provider_Speciality] [varchar](60) NOT NULL,          -- The provider's specialty
	[Has_Existing_Labcodes_Configuration] [int] NOT NULL,  -- Flag indicating if there is an existing PM_Codes entry linking thr provider and provided interface, 1= yes, 0 = No
	[labList_ID] [int] null,                                   -- this will be the labid 
	[LabCodes_ID] [int] NULL								   -- the PK of the lab Codes table. will only be populated if [Has_Existing_ADTInMHD_Configuration] = 1
) ON [PRIMARY]




end




-- Logic Gate to determine witch match method to use 
  if (@Match_Method = 1)
--/////////////// Section 1 Begin Match Method 1 ////////////////////////////////////////////////////////////////////////////////////////////////////
begin 


-- //////////////// Section 1.1  Load Facilities temp table #Facilities_M1 ////////////////////////////////////////////////////////////////////////////////////////
-- create a temp table containing active facilities and determine if they are properly configured for the provided interface 

begin





-- facility must be configured to interface with the lab

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
case when 
li.facilityid is not null then 1 else 0 end as Facility_is_related_to_Lab
into #Facilities_M1
from mobiledoc_R09.dbo.edi_facilities as fac with (nolock)
left join 
(
 select facilityid
 from mobiledoc_R09.dbo.labinterfaceinfo as li  with (nolock)
 join  mobiledoc_R09.dbo.lablist as ll  with (nolock) on ( li.labid = ll.id)
 where 1=1 
 and ll.deleteflag = 0
 and li.labid = @LabList_ID

group by facilityid -- should already be distinct since the composite key is region, facility, and labid
) as  li on (li.facilityid = fac.Id )

where 1=1 
and POS = 11 -- office
and fac.DeleteFlag = 0
and fac.code not like 'zz%'


end




-- //////////////// Section 1.2  Load Facilities temp table #Providers_M1////////////////////////////////////////////////////////////////////////////////////////
-- -- create a temp table containing active Providers and determine if they are properly configured for the provided interface 
begin 







--drop table #Providers_M1

select distinct 
dr.doctorID, 
dr.FacilityId, 
dr.Provider_LastName, 
dr.Provider_FirstName,
npi, 
Provider_Speciality,
Code as LabCodes_COde,
case 
when ltrim(rtrim(hl7id)) = '' then null 
else hl7id 
end as hl7id,

case when lc.labcodes_id is not null 
then 1 else 0
end as Has_Existing_LabCodes_Configuration,
labcodes_id,
@LabList_ID as Lablist_id, 

case 
when  lc.Code = dr.NPI 
and ltrim(rtrim(dr.NPI)) <> ''
and dr.NPI not like '9999999%'
and dr.NPI not like '0000000%'
then 1 
else 0
end as Is_Provider_Configured_for_Correctly
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
where Groupid = 58 -- user groups to exclude

and userid is not null
	)
) as dr
left join 
(
select *,
-- since there are a handful of duplicates, need to filter down to one row by defaulting to the latest ID created
ROW_NUMBER () over (partition by  itemid order by labcodes_Id desc ) as Is_Latest 
from mobiledoc_R09.dbo.labcodes lc with (nolock)
where lc.labId = @LabList_ID  -- @Lab_Name
and lc.flag = 'D'

) as lc on ( lc.itemId= dr.doctorID and lc.Is_Latest = 1 ) 
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
and doctorID in (Select doctorID from #Providers_M1)
and facilityId in (Select facilityId from #Facilities_M1)
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
Ltrim(Rtrim(p.Npi))  as labCodes_Code , -- this is the value we will set for the labCodes_Code value, 
cast (Ltrim(Rtrim(Npi)) as varchar (30) )  as Doctors_Hl7id,
p.Provider_Speciality,  
p.Has_Existing_LabCodes_Configuration, 
p.Lablist_id as Lablist_id,
p.labcodes_id
from #Providers_M1 as p
join #Prov_with_Upcoming_Appt_M1 as  apt on (  apt.doctorID = p.doctorID and apt.facilityId = p.FacilityId  )
join #Facilities_M1 as f on (f.id = p.FacilityId )
where 1=1
and p.Is_Provider_Configured_for_Correctly = 0
and f.Facility_is_related_to_Lab = 1  -- facility is configured for  the lab

-- paramaterize @STartDate and EndDate of encounters 



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
--begin

---- 

--end 


--/////////////// Final Section: Insert into  [Automation_R09].[dbo].[InterfaceMapping_Log] ////////////////////////////////////////////////////////////////////////////////////////////////////
-- Write Inserts/updates to #Pre_Merge_Results and then perform merge against [Automation_R09].[dbo].[InterfaceMapping_Log]


begin
-- write to team loging table

Select 
region_id as Region_ID,
'LabCodes' as Mapping_Type, 
'Insert' as Action_Type,
Ecw_Doctorid as DoctorID,
ECW_Facilityid as EDI_Facilities_ID, 
null  as PMList_ID,
null  as PMCodes_ID,
null as PMCodes_EcwCode,
null as PMCodes_ExternalCode,
Null as PMcodes_Flag,
labList_ID as LabList_ID, 
LabCodes_ID as LabCodes_ID,
LabCodes_Code as LabCodes_Code,
'D' as LabCodes_Flag,
Doctors_Hl7id, 
null as Edi_Facilities_HL7id,
0 as Is_Implemented,
null as Last_Encounter_Date,
getutcdate () as CreatedDate_UTC, 
null as ModifiedDate_UTC
into #Pre_Merge_Results
from #FinalResults
where 1=1 
and Has_Existing_Labcodes_Configuration = 0
and LabCodes_ID is  null -- if there is no labcode_id already in existence then we will need to insert a new one 

union all

-- now if there are any to update insert them into the mapping log table with a action type of 'U' for update

Select
region_id as Region_ID,
'LabCodes' as Mapping_Type, 
'Update' as Action_Type,
Ecw_Doctorid as DoctorID,
ECW_Facilityid as EDI_Facilities_ID, 
null  as PMList_ID,
null  as PMCodes_ID,
null as PMCodes_EcwCode,
null as PMCodes_ExternalCode,
Null as PMcodes_Flag,
labList_ID as LabList_ID, 
LabCodes_ID as LabCodes_ID,
LabCodes_Code as LabCodes_Code,
'D' as LabCodes_Flag,
Doctors_Hl7id, 
null as Edi_Facilities_HL7id,
0 as Is_Implemented,
null as Last_Encounter_Date,
getutcdate () as CreatedDate_UTC, 
null as ModifiedDate_UTC
from #FinalResults
where 1=1 
and Has_Existing_Labcodes_Configuration = 1
and LabCodes_ID is not null



-- in the event that we this proc runs before the latest changes have been implemented, but the providers info has changed, we want to update the existing record set to be implemented with the latest info

  MERGE [Automation_R09].[dbo].[InterfaceMappingLog] AS Target
    USING #Pre_Merge_Results	AS Source
    ON source.DoctorID = Target.DoctorID 
    and source.LabList_ID = Target.LabList_ID 
	and Source.Is_Implemented = target.Is_Implemented  -- including this in join condition because the source.is_implemented will always be 0, and we only want to update records that have not yet been implemented 
	and source.Mapping_Type = Target.Mapping_Type
    -- For Inserts
    WHEN NOT MATCHED BY Target THEN
        INSERT (Mapping_Type,Action_Type,	DoctorID,EDI_Facilities_ID,	PMList_ID,	PMCodes_ID,	PMCodes_EcwCode,	PMCodes_ExternalCode,	PMcodes_Flag,	LabList_ID,	LabCodes_ID,	LabCodes_Code,	LabCodes_Flag,	Doctors_Hl7id,	Edi_Facilities_HL7id,	Is_Implemented, Last_Encounter_Date,	CreatedDate_UTC,ModifiedDate_UTC) 
        VALUES (Source.Mapping_Type,Source.Action_Type,Source.DoctorID,Source.EDI_Facilities_ID,Source.PMList_ID,	Source.PMCodes_ID,	Source.PMCodes_EcwCode,	Source.PMCodes_ExternalCode,	Source.PMcodes_Flag,	Source.LabList_ID,	Source.LabCodes_ID,	Source.LabCodes_Code,	Source.LabCodes_Flag,	Source.Doctors_Hl7id,	Source.Edi_Facilities_HL7id,	Source.Is_Implemented, source.Last_Encounter_Date,	Source.CreatedDate_UTC,Source.ModifiedDate_UTC)
    
    -- For Updates
    WHEN MATCHED THEN UPDATE SET
        Target.EDI_Facilities_ID	= Source.EDI_Facilities_ID,
        Target.LabCodes_Code		= Source.LabCodes_Code,
        Target.Action_Type		    = Source.Action_Type,
		target.LabCodes_ID           = Source.LabCodes_ID,
		Target.Doctors_Hl7id		= Source.Doctors_Hl7id;


end


end



end
GO


