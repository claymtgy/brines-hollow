class_name WeaponDef
extends Resource
## Defines weapons, harvesting armaments, and tactical tools for coastal & underwater combat.

enum WeaponType {
	CUTLASS,          ## Fast sweeping blade, parry-riposte windows
	HARPOON,          ## Long reach thrust, tether cable retrieval
	ANCHOR_MAUL,      ## Heavy crushing bludgeon, breaks carapace & voxels
	SPEARGUN,         ## Ranged underwater quarrel thrower
	TRAPPER_NET,      ## Entangles, weighs down, and drags creatures
	TIDAL_LANTERN,    ## Occult bioluminescent ray emitter
	BOW,              ## High-arc ranged archery with variable draw tension
	FLINTLOCK         ## High-impact black powder burst pistol
}

enum DamageType {
	SLASH,            ## Cuts flesh, kelp, sails
	PIERCE,           ## Punctures armor and deep fish
	BLUNT,            ## High stagger, cracks shells and rock
	OCCULT,           ## Pierces abyssal shadows, illuminates wraiths
	TETHER            ## Non-lethal snag and grapple
}

@export var id: StringName = &""
@export var name: String = ""
@export var weapon_type: WeaponType = WeaponType.CUTLASS
@export var primary_damage_type: DamageType = DamageType.SLASH

## Combat performance
@export var base_damage: int = 10
@export var attack_rate: float = 1.0             ## Attacks per second
@export var reach_m: float = 2.0                 ## Melee strike range or projectile start
@export var stamina_per_swing: float = 12.0
@export var stagger_power: float = 1.0           ## Impulse applied to target

## Water mechanics
@export var underwater_efficiency: float = 0.5   ## Swing penalty in water (1.0 = full speed, 0.4 = sluggish)
@export var is_ranged: bool = false
@export var projectile_speed_m_s: float = 0.0
@export var tether_length_m: float = 0.0         ## Harpoon or net cable length

## Voxel interaction
@export var breaks_rock: bool = false
@export var harvests_kelp: bool = false


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_type: WeaponType = WeaponType.CUTLASS,
	p_damage: int = 10,
	p_reach: float = 2.0
) -> void:
	id = p_id
	name = p_name
	weapon_type = p_type
	base_damage = p_damage
	reach_m = p_reach
