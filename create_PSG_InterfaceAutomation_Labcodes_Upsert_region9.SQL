
USE [automation_R09]
GO

/****** Object:  StoredProcedure [dbo].[InterfaceAutomation_Labcodes_Upsert]    Script Date: 8/1/2022 8:20:50 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO












CREATE PROCEDURE [dbo].[InterfaceAutomation_Labcodes_Upsert] 
AS
BEGIn



/*
Created by: Alex Wright 


this is part of the interface automation project
 
Intent: this proc will replicate the update/insert functionality of ECW for the Lab interface Dashboard mapping for Lab interface configuration
this proc, is meant to be agnostic of what specific Lab we are configuring, becuase we have already set the values to be used in the [[xrdcwpdbsecw02].[eCWStage].[dbo].[InterfaceMappingLog]  table
seperate procedures handle the determine when/how to configure the provider, but this procs function is only to implement what has been quued 

the [automation_R09].[dbo].[InterfaceMappingLog] is our central hub, where we que up interfaces to be automatically updated
in this proc, we will query that table, restrincting only to non-implemeted labcodes mappings for region 9

the following ecw Tables will be updated/inserted into 
1. Doctors
2. labcodes
3. InterfaceDashboardLogs

once the update/inserts have been made, we will then update [xrdcwpdbsecw02].[eCWStage].[dbo].[InterfaceMappingLog] with the new IDs inserted and set the implemented flag to 1 

*Note: this will need to be called by a service account that can do the following
	- enable linked server between the replicated server xrdcwpdbsecw02 and the region 9 prod server FWDCWPDBSECW09, so that we can read/write from/to xrdcwpdbsecw02 while connected to FWDCWPDBSECW09
	- permission to update the following tables 
		- [Mobiledoc_R09].dbo.Doctors
		- [Mobiledoc_R09].dbo.Labcodes
		- [Mobiledoc_R09].dbo.interfacedashboardlogs
	- permission to update [automation_R09].[dbo].[InterfaceMappingLog]
*/



-- get the System userid for logging 
Declare @SystemUser varchar(10)
set @SystemUser =
(
Select top 1 uid
from Mobiledoc_R09.dbo.users with (nolock)
where 1=1 
and uname = 'Interface_System_User'
and delFlag = 0
)



-- first get the labcodes we want to map
-- the values used have been established by another proc, thus making this proc agnostic to any one type of pmcode interface 
select id ,doctorid, labcodes_id, LabCodes_Code, LabCodes_Flag, @SystemUser as Userid_for_log, LabList_ID
into #LabCodes_to_Configure
  FROM [automation_R09].[dbo].[InterfaceMappingLog] with (nolock)
  where 1=1 
  and mapping_type = 'Labcodes'
  and is_implemented = 0


---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- if there is already a labcodes entry, then we don't need to insert a new one, and just update the existing to use the correct values
-- this will most likely occur in the event where a NPI or something is mistyped in the fronted when setting up the configuration

Update Mobiledoc_R09.dbo.labcodes
Set code = ltc.LabCodes_Code
from Mobiledoc_R09.dbo.labcodes  as lc with (nolock)
join #labcodes_to_Configure as ltc on (ltc.labcodes_id = lc.labcodes_id)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- if ltc.labcodes_id is  null, then we need to insert a new row into the labcodes table
--we will want to catch the new ids that are generated on the output so we can update our [InterfaceMappingLog] table



create table #CatchNewIds
(

[labcodes_id] [int] not null,
	[labid] [int] NOT NULL,
	[itemId] [int] NOT NULL,
	
)




insert into Mobiledoc_R09.dbo.labcodes
OUTPUT inserted.labcodes_id, inserted.labid, inserted.itemId INTO #CatchNewIds
Select 
LabList_ID as LabID, 
doctorid as Itemid, 
LabCodes_Code as code, 
LabCodes_Flag as Flag, 
'' as Category, 
'' as PrevCode,
null as Abnpice
from #labcodes_to_Configure
where 1=1
and labcodes_id is null 



---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------


-- insert into logging table 
insert into Mobiledoc_R09.dbo.interfacedashboardlogs
select 
LabList_ID as Interfaceid, 
0 as interfaceType, 
Userid_for_log as USERID , -- UID of the Interface_System_User
getdate() as UpdatedDateTime,
labcodes_Flag as Flag, 
LabCodes_Code as value,
DoctorID as KeyField
from #labcodes_to_Configure
where 1=1

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------


--- now that we have made the updates, we will need to update the [InterfaceMappingLog] to reflect the changes 


update [automation_R09].[dbo].[InterfaceMappingLog]
set is_implemented = 1, 
labcodes_id = coalesce (new.labcodes_id, iml.labcodes_id),  -- set labcodes_id field to the new id on inserts, if it is an update then it will remain the same
modifiedDate_utc = GETUTCDATE()
from [automation_R09].[dbo].[InterfaceMappingLog] as iml with (nolock) 
join #labcodes_to_Configure as ltc on (ltc.id = iml.id)  -- joining on the unique key of the interfacemappinglog table
 join #CatchNewIds as new on (new.itemId = iml.doctorid  and new.labid = iml.LabList_ID ) 
where 1=1 -- the join on the pk id should be enoug, but the rest of the where clause is just to be safe
  and iml.region_id = 9
  and iml.mapping_type = 'labcodes'
  and iml.is_implemented = 0;



  end