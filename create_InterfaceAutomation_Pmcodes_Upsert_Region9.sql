USE [automation_R09]
GO

/****** Object:  StoredProcedure [dbo].[PSG_Load_InterfaceMappingLog_Master]    Script Date: 8/1/2022 8:20:50 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO












CREATE PROCEDURE [dbo].[InterfaceAutomation_Pmcodes_Upsert] 
AS
BEGIn



/*
Created by: Alex Wright 


this is part of the interface automation projectHJH
 
Intent: this proc will replicate the update/insert functionality of ECW for the PM interface Dashboard mapping for PM interface configuration
this proc, is meant to be agnostic of what specific PM we are configuring, becuase we have already set the values to be used in the [[xrdcwpdbsecw02].[eCWStage].[dbo].[InterfaceMappingLog]  table
seperate procedures handle the determine when/how to configure the provider, but this procs function is only to implement what has been quued 

the [automation_R09][dbo].[InterfaceMappingLog] is our central hub, where we que up interfaces to be automatically updated
in this proc, we will query that table, restrincting only to non-implemeted PMCodes mappings for region 9

the following ecw Tables will be updated/inserted into 
1. Doctors
2. Pmcodes
3. InterfaceDashboardLogs

once the update/inserts have been made, we will then update [[automation_R09][eCWStage].[dbo].[InterfaceMappingLog] with the new IDs inserted and set the implemented flag to 1 

*Note: this will need to be called by a service account that can do the following
	- enable linked server between the replicated server xrdcwpdbsecw02 and the region 9 prod server FWDCWPDBSECW09, so that we can read/write from/to xrdcwpdbsecw02 while connected to FWDCWPDBSECW09
	- permission to update the following tables 
		- [mobiledoc_R09].dbo.Doctors
		- [mobiledoc_R09].dbo.Pmcodes
		- [mobiledoc_R09].dbo.interfacedashboardlogs
	- permission to update [automation_R09].[dbo].[InterfaceMappingLog]
*/



-- get the System userid for logging 
Declare @SystemUser varchar(10)
set @SystemUser =
(
Select top 1 uid
from mobiledoc_R09.dbo.users with (nolock)
where 1=1 
and uname = 'Interface_System_User'
and delFlag = 0
)



-- first get the pmcodes we want to map
-- the values used have been established by another proc, thus making this proc agnostic to any one type of pmcode interface 
select id ,doctorid, doctors_hl7id, pmcodes_id, pmcodes_ecwcode, PMCodes_externalCode, pmlist_id, PMCodes_Flag, @SystemUser as Userid_for_log
into #PmCodes_to_Configure
  FROM [automation_R09].[dbo].[InterfaceMappingLog] with (nolock)
  where 1=1 
  and mapping_type = 'PMCodes'
  and is_implemented = 0


  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Update Doctors table

update mobiledoc_R09.dbo.Doctors
set hl7id = ptc.doctors_hl7id
from mobiledoc_R09.dbo.Doctors as dr with (nolock)
join #PmCodes_to_Configure as ptc on (ptc.doctorid = dr.doctorID)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- if there is already a Pmcodes entry, then we don't need to insert a new one, and just update the existing to use the correct values
-- this will most likely occur in the event where a NPI or something is mistyped in the fronted when setting up the configuration

Update mobiledoc_R09.dbo.Pmcodes
Set ECWCODE = ptc.pmcodes_ecwcode, 
 ExternalCode = ptc.PMCodes_externalCode
from mobiledoc_R09.dbo.Pmcodes  as pm with (nolock)
join #PmCodes_to_Configure as ptc on (ptc.pmcodes_id = pm.id)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- if ptc.pmcodes_id is  null, then we need to insert a new row into the pmcodes table
--we will want to catch the new ids that are generated on the output so we can update our [InterfaceMappingLog] table

create table #CatchNewIds
(

[Id] [int] not null,
	[PMId] [int] NOT NULL,
	[itemId] [int] NOT NULL,
	
)



insert into mobiledoc_R09.dbo.pmcodes
OUTPUT inserted.Id, inserted.PMId, inserted.itemId INTO #CatchNewIds
Select 
PMList_ID as PMID, 
DoctorID as Itemid, 
PMCodes_EcwCode as ECWCODE, 
PMCodes_ExternalCode as ExternalCode, 
PMCodes_Flag as Flag, 
'' as Category 
from #PmCodes_to_Configure
where 1=1
and pmcodes_id is null 

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------


-- insert into logging table 
insert into mobiledoc_R09.dbo.interfacedashboardlogs
select 
PMList_ID as Interfaceid, 
1 as interfaceType, 
Userid_for_log as USERID , -- UID of the Interface_System_User
getdate() as UpdatedDateTime,
PMCodes_Flag as Flag, 
concat (PMCodes_ExternalCode , ':', Doctors_HL7ID  ) as value,
DoctorID as KeyField
from #PmCodes_to_Configure
where 1=1

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- now that we have made the updates, we will need to update the [InterfaceMappingLog] to reflect the changes 

update [automation_R09].[dbo].[InterfaceMappingLog]
set is_implemented = 1, 
pmcodes_id = coalesce (new.Id, iml.pmcodes_id),  -- set pmcodes_id field to the new id on inserts, if it is an update then it will remain the same
modifiedDate_utc = GETUTCDATE()
from [automation_R09].[dbo].[InterfaceMappingLog] as iml with (nolock) 
join #PmCodes_to_Configure as ptc on (ptc.id = iml.id)  -- joining on the unique key of the interfacemappinglog table
 join #CatchNewIds as new on (new.itemId = iml.doctorid  and new.PMId = iml.pmlist_id ) 
where 1=1 -- the join on the pk id should be enoug, but the rest of the where clause is just to be safe
  and iml.mapping_type = 'PMCodes'
  and iml.is_implemented = 0;


  

  end