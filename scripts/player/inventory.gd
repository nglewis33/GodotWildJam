class_name Inventory
extends Node
## What the player is carrying. Get it with Inventory.of(player).

signal changed

var items: Array[String] = []


static func of(owner: Node) -> Inventory:
	var inv := owner.get_node_or_null("Inventory") as Inventory
	if inv == null:
		inv = Inventory.new()
		inv.name = "Inventory"
		owner.add_child(inv)
	return inv


func add(id: String) -> void:
	items.append(id)
	changed.emit()


func has(id: String) -> bool:
	return items.has(id)


func remove(id: String) -> void:
	items.erase(id)
	changed.emit()
