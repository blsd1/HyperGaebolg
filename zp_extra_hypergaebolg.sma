#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <fakemeta_util>
#include <hamsandwich>
#include <cstrike>
#include <fun>
#include <zombieplague>

#define PLUGIN "Hyper-gaebolg"
#define VERSION "1.0"
#define AUTHOR "ketamine"

#define SPEAR 200 // why not
#define SPEAR_SPEED 1500
#define SPEAR_EXP_RADIUS 100
#define SPEAR_DAMAGE 95 // 95: Human | 560: Zombie
#define SPEAR_KNOCK 1000

#define TIME_DRAW 0.75
#define TIME_RELOAD 2.5
#define TIME_EXPLOSION 1.0

#define OLD_WMODEL "models/w_ak47.mdl"
#define PLAYER_ANIMEXT "carbine"

#define SPEAREX_CLASSNAME "ef_spearex"
#define SPEAREX2_CLASSNAME "ef_spearex2"
#define TASK_RELOAD 13320141

#define V_MODEL "models/v_speargunex.mdl"
#define P_MODEL "models/p_speargunex.mdl"
#define W_MODEL "models/w_speargunex.mdl"
#define S_SPEARGUNEX "models/speargunex_spear.mdl"
#define S_SPEARGUNEX2 "models/speargunex_spear2.mdl"

new const SpearSounds[5][] = 
{
	"weapons/speargunex_shoot1.wav",
	"weapons/speargunex_shoot2.wav",
	"weapons/speargun_hit.wav",
	"weapons/speargunex_exp.wav",
	"weapons/speargunex_exp2.wav"
}

new const SpearSoundsGeneric[7][] = 
{
	"weapons/speargunex_draw.wav",
	"weapons/speargunex_draw_empty.wav",
	"weapons/speargunex_reload.wav",
	"weapons/speargunex_spin1_1.wav",
	"weapons/speargunex_spin1_2.wav",
	"weapons/speargunex_spin2_1.wav",
	"weapons/speargunex_spin2_2.wav"
}



new const ExplosionSpr[] = "sprites/spear_exp.spr"

const pev_user = pev_iuser1
const pev_touched = pev_iuser2
const pev_attached = pev_iuser3
const pev_hitgroup = pev_iuser4
const pev_time = pev_fuser1
const pev_time2 = pev_fuser2

const m_iLastHitGroup = 75

#define CSW_SPEAR CSW_AK47
#define weapon_spear "weapon_ak47"

// MACROS
#define Get_BitVar(%1,%2) (%1 & (1 << (%2 & 31)))
#define Set_BitVar(%1,%2) %1 |= (1 << (%2 & 31))
#define UnSet_BitVar(%1,%2) %1 &= ~(1 << (%2 & 31))

new g_IsAlive, g_TempAttack, g_HamBot_Register, g_Shoot
new g_Had_Spear, g_Spear[33], Float:CheckDelay[33], g_CurrentSpear[33]
new g_MsgWeaponList, g_MsgCurWeapon, g_MsgAmmoX
new g_SprId_LaserBeam, g_SprId_Exp,g_WeaponState[33], Float:g_TimeCharge[33], g_SpeargunEx_Exp,g_SprId_SpearExExp,g_Old_Weapon[33]
new g_ItemID_kar
enum
{
	WEAPON_NONE = 0,
	WEAPON_STARTCHARGING,
	WEAPON_WAITCHARGING,
	WEAPON_CHARGING,
	WEAPON_FINISHCHARGING
}

// Vars

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	
	register_event("CurWeapon", "Event_CurWeapon", "be", "1=1")
	register_event("DeathMsg", "Event_Death", "a")
	
	register_think(SPEAREX_CLASSNAME, "SpearExThink")
	register_touch(SPEAREX_CLASSNAME, "*", "SpearExTouch")
	register_think(SPEAREX2_CLASSNAME, "SpearExThink2")
	register_touch(SPEAREX2_CLASSNAME, "*", "SpearExTouch2")
	
	register_forward(FM_UpdateClientData, "fw_UpdateClientData_Post", 1)
	register_forward(FM_CmdStart, "fw_CmdStart")
	register_forward(FM_SetModel, "fw_SetModel")	
	register_forward(FM_EmitSound, "fw_EmitSound")
	register_forward(FM_TraceLine, "fw_TraceLine")
	register_forward(FM_TraceHull, "fw_TraceHull")	
	
	RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn_Post", 1)
	RegisterHam(Ham_Weapon_WeaponIdle, weapon_spear, "fw_Weapon_WeaponIdle_Post", 1)
	RegisterHam(Ham_Item_AddToPlayer, weapon_spear, "fw_Item_AddToPlayer_Post", 1)

	g_MsgWeaponList = get_user_msgid("WeaponList")
	g_MsgCurWeapon = get_user_msgid("CurWeapon")
	g_MsgAmmoX = get_user_msgid("AmmoX")
}

public plugin_precache()
{
	engfunc(EngFunc_PrecacheModel, V_MODEL)
	engfunc(EngFunc_PrecacheModel, P_MODEL)
	engfunc(EngFunc_PrecacheModel, W_MODEL)
	engfunc(EngFunc_PrecacheModel, S_SPEARGUNEX)
	engfunc(EngFunc_PrecacheModel, S_SPEARGUNEX2)
	for(new i = 0; i < sizeof(SpearSounds); i++)
		engfunc(EngFunc_PrecacheSound, SpearSounds[i])
	for(new i = 0; i < sizeof(SpearSoundsGeneric); i++)
		engfunc(EngFunc_PrecacheGeneric, SpearSoundsGeneric[i])
	g_SpeargunEx_Exp =  engfunc(EngFunc_PrecacheModel, S_SPEARGUNEX)
	g_SprId_LaserBeam = engfunc(EngFunc_PrecacheModel, "sprites/laserbeam.spr")
	g_SprId_Exp = engfunc(EngFunc_PrecacheGeneric, ExplosionSpr)
	g_SprId_SpearExExp = engfunc(EngFunc_PrecacheGeneric, "sprites/ef_summonex_charging_exp.spr")
	
	g_ItemID_kar = zp_register_extra_item("Hyper-Gaebolg", 350, ZP_TEAM_HUMAN)
}

public client_putinserver(id)
{
	if(is_user_bot(id) && !g_HamBot_Register)
	{
		g_HamBot_Register = 1
		set_task(0.1, "Do_RegisterHamBot", id)
	}
	
	UnSet_BitVar(g_TempAttack, id)
	UnSet_BitVar(g_IsAlive, id)
}

public client_disconnect(id)
{
	UnSet_BitVar(g_TempAttack, id)
	UnSet_BitVar(g_IsAlive, id)
}

public Do_RegisterHamBot(id)
{
	RegisterHamFromEntity(Ham_Spawn, id, "fw_PlayerSpawn_Post", 1)
}

public zp_extra_item_selected(id, itemid)
{
	// Check if player selected Hyper-Gaebolg
	if(itemid != g_ItemID_kar)
		return
	
	// Give the weapon to the player
	Get_Spear(id)
}

public Get_Spear(id)
{
	Set_BitVar(g_Had_Spear, id)
	UnSet_BitVar(g_Shoot, id)
	g_Spear[id] = SPEAR
	g_WeaponState[id] = 0
	give_item(id, weapon_spear)
	
	update_ammo(id, -1, g_Spear[id])
}

public Remove_Spear(id)
{
	UnSet_BitVar(g_Had_Spear, id)
	UnSet_BitVar(g_Shoot, id)
	g_Spear[id] = 0
	g_WeaponState[id] = 0
	remove_task(id+TASK_RELOAD)
}

public Event_CurWeapon(id)
{
	if(!Get_BitVar(g_IsAlive, id))
		return
	
	if(Get_BitVar(g_Had_Spear, id) && (get_user_weapon(id) == CSW_SPEAR && g_Old_Weapon[id] != CSW_SPEAR))
	{ // Draw
		set_pev(id, pev_viewmodel2, V_MODEL)
		set_pev(id, pev_weaponmodel2, P_MODEL)
		
		Set_WeaponAnim(id, 2)
		
		set_pdata_string(id, (492) * 4, PLAYER_ANIMEXT, -1 , 20)
		Set_Player_NextAttack(id, TIME_DRAW)
		
		remove_task(id+TASK_RELOAD)
		update_ammo(id, -1, g_Spear[id])
	} 
	
	g_Old_Weapon[id] = get_user_weapon(id)
}


public Event_Death()
{
	static Victim; Victim = read_data(2)
	UnSet_BitVar(g_IsAlive, Victim)
}

public fw_UpdateClientData_Post(id, sendweapons, cd_handle)
{
	if(!Get_BitVar(g_IsAlive, id))
		return FMRES_IGNORED	
	if(get_user_weapon(id) == CSW_SPEAR && Get_BitVar(g_Had_Spear, id))
		set_cd(cd_handle, CD_flNextAttack, get_gametime() + 0.001) 
	
	return FMRES_HANDLED
}

public fw_SetModel(entity, model[])
{
	if(!pev_valid(entity))
		return FMRES_IGNORED
	
	static Classname[64]
	pev(entity, pev_classname, Classname, sizeof(Classname))
	
	if(!equal(Classname, "weaponbox"))
		return FMRES_IGNORED
	
	static id
	id = pev(entity, pev_owner)
	
	if(equal(model, OLD_WMODEL))
	{
		static weapon
		weapon = fm_get_user_weapon_entity(entity, CSW_SPEAR)
		
		if(!pev_valid(weapon))
			return FMRES_IGNORED
		
		if(Get_BitVar(g_Had_Spear, id))
		{
			UnSet_BitVar(g_Had_Spear, id)
			
			set_pev(weapon, pev_impulse, 1332014)
			set_pev(weapon, pev_iuser4, g_Spear[id])
			
			engfunc(EngFunc_SetModel, entity, W_MODEL)
			Remove_Spear(id)
			
			return FMRES_SUPERCEDE
		}
	}

	return FMRES_IGNORED;
}

public fw_CmdStart(id, UcHandle, Seed)
{
	if(!Get_BitVar(g_IsAlive, id))
		return
	if(get_user_weapon(id) != CSW_SPEAR || !Get_BitVar(g_Had_Spear, id))
		return

	static CurButton; CurButton = get_uc(UcHandle, UC_Buttons)
	static Ent; Ent = fm_get_user_weapon_entity(id, CSW_SPEAR)
	if(CurButton & IN_ATTACK)
	{
		if(get_pdata_float(id, 83, 5) > 0.0)
			return
		
		CurButton &= ~IN_ATTACK
		set_uc(UcHandle, UC_Buttons, CurButton)

		if(get_gametime() - TIME_RELOAD > CheckDelay[id])
		{
			Spearex_Shooting(id,1)
			CheckDelay[id] = get_gametime()
		}
	} 
	if(!pev_valid(Ent)) return
	if(CurButton & IN_ATTACK2) 
	{
		CurButton &= ~IN_ATTACK2
		set_uc(UcHandle, UC_Buttons, CurButton)
		
		if(get_pdata_float(Ent, 46, 4) > 0.0 || get_pdata_float(Ent, 47, 4) > 0.0) 
			return
		if(!g_Spear[id])
			return
			
		switch(g_WeaponState[id])
		{
			case WEAPON_NONE: 
			{
				Set_WeaponAnim(id,0)
				Set_WeaponIdleTime(id, CSW_SPEAR, 0.5)
				Set_Player_NextAttack(id, 0.5)
				
				g_WeaponState[id] = WEAPON_STARTCHARGING
			}
			case WEAPON_STARTCHARGING:
			{
				Set_WeaponAnim(id,4)
				Set_WeaponIdleTime(id, CSW_SPEAR, 0.35)
				Set_Player_NextAttack(id, 0.35)
				
				g_TimeCharge[id] = get_gametime()
				g_WeaponState[id] = WEAPON_WAITCHARGING
			}
			case WEAPON_WAITCHARGING:
			{
				Set_WeaponAnim(id,5)
				Set_WeaponIdleTime(id, CSW_SPEAR, 0.35)
				Set_Player_NextAttack(id, 0.35)
				
				g_WeaponState[id] = WEAPON_WAITCHARGING
				
				if(get_gametime() >= (g_TimeCharge[id] + 0.5))
				{
					Set_WeaponAnim(id,6)
					Set_WeaponIdleTime(id, CSW_SPEAR, 0.35)
					Set_Player_NextAttack(id, 0.35)
					
					g_WeaponState[id] = WEAPON_FINISHCHARGING
				}
			}
			case WEAPON_FINISHCHARGING:
			{
				Set_WeaponAnim(id,7)
				Set_WeaponIdleTime(id, CSW_SPEAR, 0.35)
				Set_Player_NextAttack(id, 0.35)
				
				g_WeaponState[id] = WEAPON_FINISHCHARGING
			}
		}
	} else {
		static OldButton; OldButton = pev(id, pev_oldbuttons)
		if(OldButton & IN_ATTACK2)
		{
			if(g_WeaponState[id] == WEAPON_WAITCHARGING)
			{
				set_pdata_float(id, 83, 0.0, 5)
				Spearex_Shooting(id,1)
			} else if(g_WeaponState[id] == WEAPON_FINISHCHARGING) {
				Spearex_Shooting(id,2)
			}
		} else {
			if(get_pdata_float(Ent, 46, 4) > 0.0 || get_pdata_float(Ent, 47, 4) > 0.0) 
				return
			
			if(g_WeaponState[id] == WEAPON_STARTCHARGING)
			{
				set_pdata_float(id, 83, 0.0, 5)
				Spearex_Shooting(id,1)
			}
			
			g_WeaponState[id] = WEAPON_NONE
		}
	}
	
}
public Spearex_Shooting(id,mode)
{
	if(g_Spear[id] <= 0)
		return
		
	Set_BitVar(g_Shoot, id)
		
	Set_BitVar(g_TempAttack, id)
	//static Ent; Ent = fm_get_user_weapon_entity(id, CSW_KNIFE)
	//if(pev_valid(Ent)) ExecuteHamB(Ham_Weapon_PrimaryAttack, Ent)
	UnSet_BitVar(g_TempAttack, id)
	
	g_Spear[id]--
	update_ammo(id, -1, g_Spear[id])
	
	if(mode==1) {
		Set_WeaponAnim(id, 3)
		emit_sound(id, CHAN_WEAPON, SpearSounds[0], VOL_NORM, ATTN_NORM, 0, PITCH_NORM)		
	} else if(mode==2) {
		Set_WeaponAnim(id, 8)
		emit_sound(id, CHAN_WEAPON, SpearSounds[1], VOL_NORM, ATTN_NORM, 0, PITCH_NORM)	
	}
	g_WeaponState[id] = WEAPON_NONE
	
	Make_FakePunch(id)
	
	Set_Player_NextAttack(id, TIME_RELOAD)
	Set_WeaponIdleTime(id, CSW_SPEAR, TIME_RELOAD)
	
		
	// Spear
	Create_Spearex(id,mode)
	
	if(task_exists(id+TASK_RELOAD)) remove_task(id+TASK_RELOAD)
	set_task(1.0, "Play_ReloadAnim", id+TASK_RELOAD)
	
	// Set Task
}


public Make_FakePunch(id)
{
	static Float:PunchAngles[3]
	PunchAngles[0] = random_float(-3.5, -7.0)
	
	set_pev(id, pev_punchangle, PunchAngles)
}

public Play_ReloadAnim(id)
{
	id -= TASK_RELOAD
	
	if(!Get_BitVar(g_IsAlive, id))
		return
	if(get_user_weapon(id) != CSW_SPEAR || !Get_BitVar(g_Had_Spear, id))
		return
	if(g_Spear[id] <= 0)
		return
		
	Set_WeaponAnim(id, 1)
}
public Create_Spearex(id,mode)
{
	static Ent; Ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
	if(!pev_valid(Ent))
		return
	
	static Float:Origin[3], Float:Target[3], Float:Angles[3], Float:Velocity[3]
	Get_Position(id, 60.0, 10.0, -5.0, Origin)
	pev(id, pev_v_angle, Angles); Angles[0] *= -1.0
	fm_get_aim_origin(id, Target)

	set_pev(Ent, pev_movetype, MOVETYPE_FLY)
	set_pev(Ent, pev_owner, id)
	if(mode==1) {
		set_pev(Ent, pev_classname, SPEAREX_CLASSNAME)
		engfunc(EngFunc_SetModel, Ent, S_SPEARGUNEX)	
		set_pev(Ent, pev_mins, Float:{-1.0, -1.0, -1.0})
		set_pev(Ent, pev_maxs, Float:{1.0, 1.0, 1.0})
		
		set_pev(Ent, pev_origin, Origin)
		set_pev(Ent, pev_angles, Angles)
		set_pev(Ent, pev_gravity, 0.01)
		
		set_pev(Ent, pev_solid, SOLID_TRIGGER)
		
		set_pev(Ent, pev_user, id)
		set_pev(Ent, pev_touched, 0)
		set_pev(Ent, pev_time, 0.0)
		
		set_pev(Ent, pev_time2, get_gametime() + 5.0)
		
		set_pev(Ent, pev_nextthink, get_gametime() + 0.1)
		
		Get_SpeedVector(Origin, Target, float(1500), Velocity)
		set_pev(Ent, pev_velocity, Velocity)
		
		g_CurrentSpear[id] = Ent
	
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
		write_byte(TE_BEAMFOLLOW)
		write_short(Ent)
		write_short(g_SprId_LaserBeam)
		write_byte(4)
		write_byte(2)
		write_byte(42)
		write_byte(255)
		write_byte(170)
		write_byte(150)
		message_end()
		
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
		write_byte(TE_BEAMFOLLOW)
		write_short(Ent)
		write_short(g_SprId_LaserBeam)
		write_byte(4)
		write_byte(2)
		write_byte(150)
		write_byte(150)
		write_byte(150)
		write_byte(150)
		message_end()
	} else if(mode==2) {
		set_pev(Ent, pev_classname, SPEAREX2_CLASSNAME)
		engfunc(EngFunc_SetModel, Ent, S_SPEARGUNEX2)	
		set_pev(Ent, pev_mins, Float:{-1.0, -1.0, -1.0})
		set_pev(Ent, pev_maxs, Float:{1.0, 1.0, 1.0})
		
		set_pev(Ent, pev_origin, Origin)
		set_pev(Ent, pev_angles, Angles)
		set_pev(Ent, pev_gravity, 0.01)
		
		set_pev(Ent, pev_solid, SOLID_TRIGGER)
		
		set_pev(Ent, pev_user, id)
		set_pev(Ent, pev_touched, 0)
		set_pev(Ent, pev_time, 0.0)
		set_pev(Ent, pev_time2, get_gametime() + 5.0)
		set_pev(Ent, pev_skin, 1)
		set_pev(Ent, pev_nextthink, get_gametime() + 0.1)
		
		Get_SpeedVector(Origin, Target, float(1500), Velocity)
		set_pev(Ent, pev_velocity, Velocity)
		
		g_CurrentSpear[id] = Ent
	
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
		write_byte(TE_BEAMFOLLOW)
		write_short(Ent)
		write_short(g_SprId_LaserBeam)
		write_byte(4)
		write_byte(2)
		write_byte(255)
		write_byte(42)
		write_byte(4)
		write_byte(150)
		message_end()
		
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
		write_byte(TE_BEAMFOLLOW)
		write_short(Ent)
		write_short(g_SprId_LaserBeam)
		write_byte(4)
		write_byte(2)
		write_byte(150)
		write_byte(150)
		write_byte(150)
		write_byte(150)
		message_end()
	}
	
	
	
}
public SpearExThink(Ent)
{
	if(!pev_valid(Ent))
		return
	if(pev(Ent, pev_flags) == FL_KILLME)
		return
		
	static Victim; Victim = pev(Ent, pev_attached)
	static Owner; Owner = pev(Ent, pev_user)
	if(is_user_connected(Owner))
	{
		static Victim; Victim = FindClosesEnemy(Ent)
		if(is_user_alive(Victim) && entity_range(Victim, Ent) <= 640.0)
		{
			static Float:Origin[3]; pev(Victim, pev_origin, Origin)
			Aim_To(Ent, Origin, 1.0, 0)
			
			static Float:Velocity[3], Float:Cur[3];
			
			pev(Ent, pev_origin, Cur)
			get_speed_vector(Cur, Origin, 2000.0, Velocity)
			set_pev(Ent, pev_velocity, Velocity)
		}
	}
	if(is_user_alive(Victim) && cs_get_user_team(Owner) != cs_get_user_team(Victim))
	{
		static Float:Origin[3]
		pev(Victim, pev_origin, Origin)
		engfunc(EngFunc_SetOrigin, Ent, Origin)
		
		if(is_user_alive(Owner))
		{
			static Float:OriginA[3]; pev(Owner, pev_origin, OriginA)
			static Float:Velocity[3]; Get_SpeedVector(OriginA, Origin, float(250), Velocity)
			
			set_pev(Victim, pev_velocity, Velocity)
		}
	}
	
	if(pev(Ent, pev_touched) && pev(Ent, pev_time) <= get_gametime())
	{
		SpearExExplosion(Ent, 0)
		set_pev(Ent, pev_flags, FL_KILLME)
		
		static Owner; Owner = pev(Ent, pev_user)
		UnSet_BitVar(g_Shoot, Owner)
	}
	
	if(pev(Ent, pev_time2) <= get_gametime())
	{
		set_pev(Ent, pev_flags, FL_KILLME)
		
		static Owner; Owner = pev(Ent, pev_user)
		UnSet_BitVar(g_Shoot, Owner)
	}
	
	set_pev(Ent, pev_nextthink, get_gametime() + 0.1)
}
public SpearExTouch(Ent, Touched)
{
	if(!pev_valid(Ent))
		return
	if(pev(Ent, pev_movetype) == MOVETYPE_NONE)
		return
	
	static Owner; Owner = pev(Ent, pev_user)
	if(is_user_alive(Touched) && cs_get_user_team(Touched) != cs_get_user_team(Owner))
	{
		set_pev(Ent, pev_movetype, MOVETYPE_FOLLOW)
		set_pev(Ent, pev_solid, SOLID_NOT)
		set_pev(Ent, pev_touched, 1)
		set_pev(Ent, pev_time, get_gametime() + 1.4)
		set_pev(Ent, pev_attached, Touched)
	}
	else
	{
		emit_sound(Ent, CHAN_BODY, SpearSounds[2], VOL_NORM, ATTN_NORM, 0, PITCH_NORM)
		set_pev(Ent, pev_movetype, MOVETYPE_NONE)
		set_pev(Ent, pev_solid, SOLID_NOT)
		set_pev(Ent, pev_touched, 1)
		set_pev(Ent, pev_time, get_gametime() + 1.4)
	}
}
public SpearExThink2(Ent)
{
	if(!pev_valid(Ent))
		return
	if(pev(Ent, pev_flags) == FL_KILLME)
		return
		
	static Victim; Victim = pev(Ent, pev_attached)
	static Owner; Owner = pev(Ent, pev_user)
	if(is_user_connected(Owner))
	{
		static Victim; Victim = FindClosesEnemy(Ent)
		if(is_user_alive(Victim) && entity_range(Victim, Ent) <= 640.0)
		{
			static Float:Origin[3]; pev(Victim, pev_origin, Origin)
			Aim_To(Ent, Origin, 1.0, 0)
			
			static Float:Velocity[3], Float:Cur[3];
			
			pev(Ent, pev_origin, Cur)
			get_speed_vector(Cur, Origin, 2000.0, Velocity)
			set_pev(Ent, pev_velocity, Velocity)
		}
	}
	if(is_user_alive(Victim) && cs_get_user_team(Owner) != cs_get_user_team(Victim))
	{
		static Float:Origin[3]
		pev(Victim, pev_origin, Origin)
		engfunc(EngFunc_SetOrigin, Ent, Origin)
		
		if(is_user_alive(Owner))
		{
			static Float:OriginA[3]; pev(Owner, pev_origin, OriginA)
			static Float:Velocity[3]; Get_SpeedVector(OriginA, Origin, float(250), Velocity)
			
			set_pev(Victim, pev_velocity, Velocity)
		}
	}
	
	if(pev(Ent, pev_touched) && pev(Ent, pev_time) <= get_gametime())
	{
		SpearExExplosion2(Ent, 0)
		set_pev(Ent, pev_flags, FL_KILLME)
		
		static Owner; Owner = pev(Ent, pev_user)
		UnSet_BitVar(g_Shoot, Owner)
	}
	
	if(pev(Ent, pev_time2) <= get_gametime())
	{
		set_pev(Ent, pev_flags, FL_KILLME)
		
		static Owner; Owner = pev(Ent, pev_user)
		UnSet_BitVar(g_Shoot, Owner)
	}
	
	set_pev(Ent, pev_nextthink, get_gametime() + 0.1)
}

public SpearExTouch2(Ent, Touched)
{
	if(!pev_valid(Ent))
		return
	if(pev(Ent, pev_movetype) == MOVETYPE_NONE)
		return
	
	static Owner; Owner = pev(Ent, pev_user)
	if(is_user_alive(Touched) && cs_get_user_team(Touched) != cs_get_user_team(Owner))
	{
		set_pev(Ent, pev_movetype, MOVETYPE_FOLLOW)
		set_pev(Ent, pev_solid, SOLID_NOT)
		set_pev(Ent, pev_touched, 1)
		set_pev(Ent, pev_time, get_gametime() + 1.4)
		set_pev(Ent, pev_attached, Touched)
	}
	else
	{
		emit_sound(Ent, CHAN_BODY, SpearSounds[2], VOL_NORM, ATTN_NORM, 0, PITCH_NORM)
		set_pev(Ent, pev_movetype, MOVETYPE_NONE)
		set_pev(Ent, pev_solid, SOLID_NOT)
		set_pev(Ent, pev_touched, 1)
		set_pev(Ent, pev_time, get_gametime() + 1.4)
	}
}

public SpearExExplosion(Ent, Remote)
{
	static Float:Origin[3]
	pev(Ent, pev_origin, Origin)
	
	// Create Explosion V1
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, Origin, 0)
	write_byte(TE_EXPLOSION)
	engfunc(EngFunc_WriteCoord, Origin[0])
	engfunc(EngFunc_WriteCoord, Origin[1])
	engfunc(EngFunc_WriteCoord, Origin[2] + 10.0)
	write_short(g_SprId_Exp)
	write_byte(20)
	write_byte(60)
	write_byte(TE_EXPLFLAG_NOSOUND)
	message_end()
	
	
	
	// Create Spark V1
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(TE_SPARKS)
	engfunc(EngFunc_WriteCoord, Origin[0])
	engfunc(EngFunc_WriteCoord, Origin[1])
	engfunc(EngFunc_WriteCoord, Origin[2])
	message_end()

	// Create Spark V2
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(TE_TAREXPLOSION)
	engfunc(EngFunc_WriteCoord, Origin[0])
	engfunc(EngFunc_WriteCoord, Origin[1])
	engfunc(EngFunc_WriteCoord, Origin[2])
	message_end()
	
	// Create Spear (Models)
	message_begin(MSG_BROADCAST,SVC_TEMPENTITY)
	write_byte(TE_BREAKMODEL)
	engfunc(EngFunc_WriteCoord, Origin[0])
	engfunc(EngFunc_WriteCoord, Origin[1])
	engfunc(EngFunc_WriteCoord, Origin[2])
	engfunc(EngFunc_WriteCoord, 100)
	engfunc(EngFunc_WriteCoord, 100)
	engfunc(EngFunc_WriteCoord, 100)
	engfunc(EngFunc_WriteCoord, random_num(-50, 50))
	engfunc(EngFunc_WriteCoord, random_num(-50, 50))
	engfunc(EngFunc_WriteCoord, random_num(-50, 50))
	write_byte(20)
	write_short(g_SpeargunEx_Exp)
	write_byte(random_num(5, 8))
	write_byte(15)
	write_byte(0)
	message_end()
	
	emit_sound(Ent, CHAN_BODY, "weapons/speargunex_exp.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM)
	static Id
	Id = pev(Ent, pev_user)
	
	if(is_user_connected(Id))
		SpearEx_Damage(Ent, Id, Origin,850)
	
	if(Remote) SpearExExplosion(Ent, 0)
}
public SpearExExplosion2(Ent, Remote)
{
	static Float:Origin[3]
	pev(Ent, pev_origin, Origin)
	
	// Create Explosion V1
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, Origin, 0)
	write_byte(TE_EXPLOSION)
	engfunc(EngFunc_WriteCoord, Origin[0])
	engfunc(EngFunc_WriteCoord, Origin[1])
	engfunc(EngFunc_WriteCoord, Origin[2] + 10.0)
	write_short(g_SprId_SpearExExp)
	write_byte(10)
	write_byte(30)
	write_byte(TE_EXPLFLAG_NOSOUND)
	message_end()
	
	emit_sound(Ent, CHAN_BODY, "weapons/speargunex_exp2.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM)
	
	
	static Id
	Id = pev(Ent, pev_user)
	
	if(is_user_connected(Id))
		SpearEx_Damage(Ent, Id, Origin,1250)
	
	if(Remote) SpearExExplosion2(Ent, 0)
}
public SpearEx_Damage(Ent, id, Float:Origin[3],damage)
{
	for(new i = 0; i < get_maxplayers(); i++)
	{
		if(!is_user_alive(i))
			continue
		if(entity_range(Ent, i) > float(200))
			continue

		if(id != i) ExecuteHamB(Ham_TakeDamage, i, 0, id, float(damage), DMG_BURN)
		Check_Knockback(i, Ent, id)
	}
}


public fw_EmitSound(id, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
	if(!Get_BitVar(g_IsAlive, id))
		return FMRES_IGNORED
	if(!Get_BitVar(g_TempAttack, id))
		return FMRES_IGNORED
		
	if(sample[8] == 'k' && sample[9] == 'n' && sample[10] == 'i')
	{
		if(sample[14] == 's' && sample[15] == 'l' && sample[16] == 'a')
			return FMRES_SUPERCEDE
		if (sample[14] == 'h' && sample[15] == 'i' && sample[16] == 't')
		{
			if (sample[17] == 'w')  return FMRES_SUPERCEDE
			else  return FMRES_SUPERCEDE
		}
		if (sample[14] == 's' && sample[15] == 't' && sample[16] == 'a')
			return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED
}

public fw_TraceLine(Float:vector_start[3], Float:vector_end[3], ignored_monster, id, handle)
{
	if(!Get_BitVar(g_IsAlive, id))
		return FMRES_IGNORED
	if(!Get_BitVar(g_TempAttack, id))
		return FMRES_IGNORED
	
	static Float:vecStart[3], Float:vecEnd[3], Float:v_angle[3], Float:v_forward[3], Float:view_ofs[3], Float:fOrigin[3]
	
	pev(id, pev_origin, fOrigin)
	pev(id, pev_view_ofs, view_ofs)
	xs_vec_add(fOrigin, view_ofs, vecStart)
	pev(id, pev_v_angle, v_angle)
	
	engfunc(EngFunc_MakeVectors, v_angle)
	get_global_vector(GL_v_forward, v_forward)

	xs_vec_mul_scalar(v_forward, 0.0, v_forward)
	xs_vec_add(vecStart, v_forward, vecEnd)
	
	engfunc(EngFunc_TraceLine, vecStart, vecEnd, ignored_monster, id, handle)
	
	return FMRES_SUPERCEDE
}

public fw_TraceHull(Float:vector_start[3], Float:vector_end[3], ignored_monster, hull, id, handle)
{
	if(!Get_BitVar(g_IsAlive, id))
		return FMRES_IGNORED
	if(!Get_BitVar(g_TempAttack, id))
		return FMRES_IGNORED
	
	static Float:vecStart[3], Float:vecEnd[3], Float:v_angle[3], Float:v_forward[3], Float:view_ofs[3], Float:fOrigin[3]
	
	pev(id, pev_origin, fOrigin)
	pev(id, pev_view_ofs, view_ofs)
	xs_vec_add(fOrigin, view_ofs, vecStart)
	pev(id, pev_v_angle, v_angle)
	
	engfunc(EngFunc_MakeVectors, v_angle)
	get_global_vector(GL_v_forward, v_forward)
	
	xs_vec_mul_scalar(v_forward, 0.0, v_forward)
	xs_vec_add(vecStart, v_forward, vecEnd)
	
	engfunc(EngFunc_TraceHull, vecStart, vecEnd, ignored_monster, hull, id, handle)
	
	return FMRES_SUPERCEDE
}



public fw_PlayerSpawn_Post(id) 
{
	Set_BitVar(g_IsAlive, id)
}

public fw_Weapon_WeaponIdle_Post(Ent)
{
	if(pev_valid(Ent) != 2)
		return HAM_IGNORED	
	static Id; Id = get_pdata_cbase(Ent, 41, 4)
	if(get_pdata_cbase(Id, 373) != Ent)
		return HAM_IGNORED	
	if(!Get_BitVar(g_Had_Spear, Id))
		return HAM_IGNORED	
		
	if(get_pdata_float(Ent, 48, 4) <= 0.1) 
	{
		Set_WeaponAnim(Id, 0)
		
		set_pdata_float(Ent, 48, 20.0, 4)
		set_pdata_string(Id, (492) * 4, PLAYER_ANIMEXT, -1 , 20)
	}
	
	return HAM_IGNORED	
}


public fw_Item_AddToPlayer_Post(Ent, id)
{
	if(!pev_valid(Ent))
		return HAM_IGNORED
		
	if(pev(Ent, pev_impulse) == 1332014)
	{
		Set_BitVar(g_Had_Spear, id)
		set_pev(Ent, pev_impulse, 0)
		
		g_Spear[id] = pev(Ent, pev_iuser4)
	}		
	g_WeaponState[id] = WEAPON_NONE
	message_begin(MSG_ONE_UNRELIABLE, g_MsgWeaponList, .player = id)
	write_string(Get_BitVar(g_Had_Spear, id) ? "weapon_speargun" : weapon_spear)
	write_byte(3) // PrimaryAmmoID
	write_byte(200) // PrimaryAmmoMaxAmount
	write_byte(-1) // SecondaryAmmoID
	write_byte(-1) // SecondaryAmmoMaxAmount
	write_byte(0) // SlotID (0...N)
	write_byte(4) // NumberInSlot (1...N)
	write_byte(CSW_SPEAR) // WeaponID
	write_byte(0) // Flags
	message_end()

	return HAM_HANDLED	
}

public update_ammo(id, Ammo, BpAmmo)
{
	message_begin(MSG_ONE_UNRELIABLE, g_MsgCurWeapon, _, id)
	write_byte(1)
	write_byte(CSW_SPEAR)
	write_byte(Ammo)
	message_end()
	
	message_begin(MSG_ONE_UNRELIABLE, g_MsgAmmoX, _, id)
	write_byte(10)
	write_byte(BpAmmo)
	message_end()
	
	cs_set_user_bpammo(id, CSW_SPEAR, BpAmmo)
}

stock Set_WeaponIdleTime(id, WeaponId ,Float:TimeIdle)
{
	static entwpn; entwpn = fm_get_user_weapon_entity(id, WeaponId)
	if(!pev_valid(entwpn)) 
		return
		
	set_pdata_float(entwpn, 46, TimeIdle, 4)
	set_pdata_float(entwpn, 47, TimeIdle, 4)
	set_pdata_float(entwpn, 48, TimeIdle + 0.5, 4)
}

stock Set_Player_NextAttack(id, Float:nexttime)
{
	set_pdata_float(id, 83, nexttime, 5)
}

stock Set_WeaponAnim(id, Anim)
{
	set_pev(id, pev_weaponanim, Anim)
	
	message_begin(MSG_ONE_UNRELIABLE, SVC_WEAPONANIM, {0, 0, 0}, id)
	write_byte(Anim)
	write_byte(pev(id, pev_body))
	message_end()
}

stock Get_Position(id,Float:forw, Float:right, Float:up, Float:vStart[])
{
	static Float:vOrigin[3], Float:vAngle[3], Float:vForward[3], Float:vRight[3], Float:vUp[3]
	
	pev(id, pev_origin, vOrigin)
	pev(id, pev_view_ofs,vUp) //for player
	xs_vec_add(vOrigin,vUp,vOrigin)
	pev(id, pev_v_angle, vAngle) // if normal entity ,use pev_angles
	
	angle_vector(vAngle,ANGLEVECTOR_FORWARD,vForward) //or use EngFunc_AngleVectors
	angle_vector(vAngle,ANGLEVECTOR_RIGHT,vRight)
	angle_vector(vAngle,ANGLEVECTOR_UP,vUp)
	
	vStart[0] = vOrigin[0] + vForward[0] * forw + vRight[0] * right + vUp[0] * up
	vStart[1] = vOrigin[1] + vForward[1] * forw + vRight[1] * right + vUp[1] * up
	vStart[2] = vOrigin[2] + vForward[2] * forw + vRight[2] * right + vUp[2] * up
}

stock Get_SpeedVector(const Float:origin1[3],const Float:origin2[3],Float:speed, Float:new_velocity[3])
{
	new_velocity[0] = origin2[0] - origin1[0]
	new_velocity[1] = origin2[1] - origin1[1]
	new_velocity[2] = origin2[2] - origin1[2]
	new Float:num = floatsqroot(speed*speed / (new_velocity[0]*new_velocity[0] + new_velocity[1]*new_velocity[1] + new_velocity[2]*new_velocity[2]))
	new_velocity[0] *= num
	new_velocity[1] *= num
	new_velocity[2] *= num
	
	return 1;
}

stock Get_Yaw(Float:Start[3], Float:End[3])
{
	static Float:Vec[3], Float:Angles[3]
	Vec = Start
	
	Vec[0] = End[0] - Vec[0]
	Vec[1] = End[1] - Vec[1]
	Vec[2] = End[2] - Vec[2]
	engfunc(EngFunc_VecToAngles, Vec, Angles)
	Angles[0] = Angles[2] = 0.0 
	
	return floatround(Angles[1])
}
stock FindClosesEnemy(entid)
{
	new Float:Dist
	new Float:maxdistance=300.0
	new indexid=0	
	for(new i=1;i<=get_maxplayers();i++){
		if(is_user_alive(i) && is_valid_ent(i) && can_see_fm(entid, i)
		&& pev(entid, pev_owner) != i && cs_get_user_team(pev(entid, pev_owner)) != cs_get_user_team(i))
		{
			Dist = entity_range(entid, i)
			if(Dist <= maxdistance)
			{
				maxdistance=Dist
				indexid=i
				
				return indexid
			}
		}	
	}	
	return 0
}

stock bool:can_see_fm(entindex1, entindex2)
{
	if (!entindex1 || !entindex2)
		return false

	if (pev_valid(entindex1) && pev_valid(entindex1))
	{
		new flags = pev(entindex1, pev_flags)
		if (flags & EF_NODRAW || flags & FL_NOTARGET)
		{
			return false
		}

		new Float:lookerOrig[3]
		new Float:targetBaseOrig[3]
		new Float:targetOrig[3]
		new Float:temp[3]

		pev(entindex1, pev_origin, lookerOrig)
		pev(entindex1, pev_view_ofs, temp)
		lookerOrig[0] += temp[0]
		lookerOrig[1] += temp[1]
		lookerOrig[2] += temp[2]

		pev(entindex2, pev_origin, targetBaseOrig)
		pev(entindex2, pev_view_ofs, temp)
		targetOrig[0] = targetBaseOrig [0] + temp[0]
		targetOrig[1] = targetBaseOrig [1] + temp[1]
		targetOrig[2] = targetBaseOrig [2] + temp[2]

		engfunc(EngFunc_TraceLine, lookerOrig, targetOrig, 0, entindex1, 0) //  checks the had of seen player
		if (get_tr2(0, TraceResult:TR_InOpen) && get_tr2(0, TraceResult:TR_InWater))
		{
			return false
		} 
		else 
		{
			new Float:flFraction
			get_tr2(0, TraceResult:TR_flFraction, flFraction)
			if (flFraction == 1.0 || (get_tr2(0, TraceResult:TR_pHit) == entindex2))
			{
				return true
			}
			else
			{
				targetOrig[0] = targetBaseOrig [0]
				targetOrig[1] = targetBaseOrig [1]
				targetOrig[2] = targetBaseOrig [2]
				engfunc(EngFunc_TraceLine, lookerOrig, targetOrig, 0, entindex1, 0) //  checks the body of seen player
				get_tr2(0, TraceResult:TR_flFraction, flFraction)
				if (flFraction == 1.0 || (get_tr2(0, TraceResult:TR_pHit) == entindex2))
				{
					return true
				}
				else
				{
					targetOrig[0] = targetBaseOrig [0]
					targetOrig[1] = targetBaseOrig [1]
					targetOrig[2] = targetBaseOrig [2] - 17.0
					engfunc(EngFunc_TraceLine, lookerOrig, targetOrig, 0, entindex1, 0) //  checks the legs of seen player
					get_tr2(0, TraceResult:TR_flFraction, flFraction)
					if (flFraction == 1.0 || (get_tr2(0, TraceResult:TR_pHit) == entindex2))
					{
						return true
					}
				}
			}
		}
	}
	return false
}

stock turn_to_target(ent, Float:Ent_Origin[3], target, Float:Vic_Origin[3]) 
{
	if(target) 
	{
		new Float:newAngle[3]
		entity_get_vector(ent, EV_VEC_angles, newAngle)
		new Float:x = Vic_Origin[0] - Ent_Origin[0]
		new Float:z = Vic_Origin[1] - Ent_Origin[1]

		new Float:radians = floatatan(z/x, radian)
		newAngle[1] = radians * (180 / 3.14)
		if (Vic_Origin[0] < Ent_Origin[0])
			newAngle[1] -= 180.0
        
		entity_set_vector(ent, EV_VEC_angles, newAngle)
	}
}
public Aim_To(iEnt, Float:vTargetOrigin[3], Float:flSpeed, Style)
{
	if(!pev_valid(iEnt))	
		return
		
	if(!Style)
	{
		static Float:Vec[3], Float:Angles[3]
		pev(iEnt, pev_origin, Vec)
		
		Vec[0] = vTargetOrigin[0] - Vec[0]
		Vec[1] = vTargetOrigin[1] - Vec[1]
		Vec[2] = vTargetOrigin[2] - Vec[2]
		engfunc(EngFunc_VecToAngles, Vec, Angles)
		Angles[0] = Angles[2] = 0.0 
		
		set_pev(iEnt, pev_v_angle, Angles)
		set_pev(iEnt, pev_angles, Angles)
	} else {
		new Float:f1, Float:f2, Float:fAngles, Float:vOrigin[3], Float:vAim[3], Float:vAngles[3];
		pev(iEnt, pev_origin, vOrigin);
		xs_vec_sub(vTargetOrigin, vOrigin, vOrigin);
		xs_vec_normalize(vOrigin, vAim);
		vector_to_angle(vAim, vAim);
		
		if (vAim[1] > 180.0) vAim[1] -= 360.0;
		if (vAim[1] < -180.0) vAim[1] += 360.0;
		
		fAngles = vAim[1];
		pev(iEnt, pev_angles, vAngles);
		
		if (vAngles[1] > fAngles)
		{
			f1 = vAngles[1] - fAngles;
			f2 = 360.0 - vAngles[1] + fAngles;
			if (f1 < f2)
			{
				vAngles[1] -= flSpeed;
				vAngles[1] = floatmax(vAngles[1], fAngles);
			}
			else
			{
				vAngles[1] += flSpeed;
				if (vAngles[1] > 180.0) vAngles[1] -= 360.0;
			}
		}
		else
		{
			f1 = fAngles - vAngles[1];
			f2 = 360.0 - fAngles + vAngles[1];
			if (f1 < f2)
			{
				vAngles[1] += flSpeed;
				vAngles[1] = floatmin(vAngles[1], fAngles);
			}
			else
			{
				vAngles[1] -= flSpeed;
				if (vAngles[1] < -180.0) vAngles[1] += 360.0;
			}		
		}
	
		set_pev(iEnt, pev_v_angle, vAngles)
		set_pev(iEnt, pev_angles, vAngles)
	}
}
stock get_speed_vector(const Float:origin1[3],const Float:origin2[3],Float:speed, Float:new_velocity[3])
{
	new_velocity[0] = origin2[0] - origin1[0]
	new_velocity[1] = origin2[1] - origin1[1]
	new_velocity[2] = origin2[2] - origin1[2]
	static Float:num; num = floatsqroot(speed*speed / (new_velocity[0]*new_velocity[0] + new_velocity[1]*new_velocity[1] + new_velocity[2]*new_velocity[2]))
	new_velocity[0] *= num
	new_velocity[1] *= num
	new_velocity[2] *= num
	
	return 1;
}
stock get_weapon_attachment(id, Float:output[3], Float:fDis = 40.0)
{ 
	static Float:vfEnd[3], viEnd[3] 
	get_user_origin(id, viEnd, 3)  
	IVecFVec(viEnd, vfEnd) 
	
	static Float:fOrigin[3], Float:fAngle[3]
	
	pev(id, pev_origin, fOrigin) 
	pev(id, pev_view_ofs, fAngle)
	
	xs_vec_add(fOrigin, fAngle, fOrigin) 
	
	static Float:fAttack[3]
	
	xs_vec_sub(vfEnd, fOrigin, fAttack)
	xs_vec_sub(vfEnd, fOrigin, fAttack) 
	
	static Float:fRate
	
	fRate = fDis / vector_length(fAttack)
	xs_vec_mul_scalar(fAttack, fRate, fAttack)
	
	xs_vec_add(fOrigin, fAttack, output)
}
public Check_Knockback(id, Ent, Owner)
{
	if(id == Owner)
	{
		static Float:Velocity[3]
		pev(id, pev_velocity, Velocity)
		
		Velocity[2] = 300.0
		
		if(Velocity[2] < 0.0)
			Velocity[2] = 100.0
		
		set_pev(id, pev_velocity, Velocity)
	}
}


/* AMXX-Studio Notes - DO NOT MODIFY BELOW HERE
*{\\ rtf1\\ ansi\\ deff0{\\ fonttbl{\\ f0\\ fnil Tahoma;}}\n\\ viewkind4\\ uc1\\ pard\\ lang1042\\ f0\\ fs16 \n\\ par }
*/
/* AMXX-Studio Notes - DO NOT MODIFY BELOW HERE
*{\\ rtf1\\ ansi\\ deff0{\\ fonttbl{\\ f0\\ fnil Tahoma;}}\n\\ viewkind4\\ uc1\\ pard\\ lang1033\\ f0\\ fs16 \n\\ par }
*/
