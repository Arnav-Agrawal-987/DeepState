extends Node
class_name InstitutionManager

# Holds references to institution nodes (simple stubs).
var institutions: Array = []

func register_institution(inst: Node) -> void:
    institutions.append(inst)

func auto_update() -> void:
    # Call `auto_update` on each registered institution if available.
    for inst in institutions:
        if inst and inst.has_method("auto_update"):
            inst.auto_update()

func rewire_graph(graph: Node) -> void:
    # Placeholder: institutions can provide weight updates to the graph
    if graph and graph.has_method("rewire_all"):
        graph.rewire_all(institutions)
