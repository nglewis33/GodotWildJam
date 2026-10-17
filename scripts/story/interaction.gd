class_name Interaction
extends RefCounted
## Decides which interactable the E key applies to when several are in range:
## the one the player's character is facing most (closer wins close calls).
##
## An interactable joins the group "interactable" and provides:
##   func interact_ready() -> bool       # enabled and within range right now
##   func interact_position() -> Vector3 # where it is, for the facing test

const DISTANCE_WEIGHT := 0.02


static func best(tree: SceneTree) -> Node:
	var player := tree.get_first_node_in_group("player") as Node3D
	if player == null or tree.paused or Cutscene.busy():
		return null
	var fwd := player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var winner: Node = null
	var top := -INF
	for n in tree.get_nodes_in_group("interactable"):
		if not n.has_method("interact_ready") or not n.interact_ready():
			continue
		var to: Vector3 = n.call("interact_position") - player.global_position
		to.y = 0.0
		var d := to.length()
		var facing := fwd.dot(to / d) if d > 0.01 else 1.0
		var score := facing - d * DISTANCE_WEIGHT
		if score > top:
			top = score
			winner = n
	return winner


static func is_best(node: Node) -> bool:
	return best(node.get_tree()) == node
