extends Node
class_name DependencyGraph

# Minimal dependency graph representation. Institutions and edges are kept simple.
var nodes: Dictionary = {}
var edges: Array = []

func rewire_all(institutions: Array) -> void:
    # Rebuild or adjust edges based on institutions' reported links.
    # Placeholder implementation: clear and create trivial edges.
    edges.clear()
    for i in range(institutions.size()):
        for j in range(institutions.size()):
            if i == j:
                continue
            edges.append({"from": i, "to": j, "weight": 1.0})

func to_dict() -> Dictionary:
    return {"nodes": nodes, "edges": edges}
