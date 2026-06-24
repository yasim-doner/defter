import re

def create_base_level():
    input_path = "g:/defter/Level1.tscn"
    output_path = "g:/defter/scenes/base_level.tscn"
    
    with open(input_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
        
    out_lines = []
    skip_node_stack = []
    
    # We want to keep only these root-level nodes and their descendants:
    allowed_nodes = {
        "Backgrounds", "Pens", "Enemies", "Player1", "Player2", "Bullets", "UI", "TileMapLayer"
    }
    
    # Track current node path / level
    node_depth = 0
    current_node_name = ""
    is_root = False
    
    for line in lines:
        line_stripped = line.strip()
        
        # Replace the script path at the very beginning
        if line.startswith('[ext_resource') and 'path="res://scripts/Level1.gd"' in line:
            line = '[ext_resource type="Script" path="res://scripts/base_level.gd" id="1_level"]\n'
            out_lines.append(line)
            continue
            
        # Parse Node definitions
        if line.startswith('[node '):
            # Parse node name and parent from header
            name_match = re.search(r'name="([^"]+)"', line)
            parent_match = re.search(r'parent="([^"]+)"', line)
            
            node_name = name_match.group(1) if name_match else ""
            parent = parent_match.group(1) if parent_match else ""
            
            if parent == ".":
                # Root-level child
                current_node_name = node_name
                if node_name in allowed_nodes:
                    skip_node_stack = []
                else:
                    skip_node_stack = [node_name]
            elif parent == "":
                # Root level node itself
                line = line.replace('name="Level1"', 'name="BaseLevel"')
                current_node_name = "BaseLevel"
                skip_node_stack = []
            else:
                # Nested child. Check if parent or ancestors are skipped.
                current_node_name = node_name
                # If we are inside a skipped branch, add this to stack
                if skip_node_stack:
                    skip_node_stack.append(node_name)
                else:
                    # Specific sub-node cleanups:
                    # Let's empty the Pens and Enemies containers by skipping their children
                    if parent in ["Pens", "Enemies"]:
                        skip_node_stack.append(node_name)
                    # Let's clear the default tilemap data from the TileMapLayer so it's a blank template
                    elif node_name == "TileMapLayer":
                        # We keep the node but will strip tile_map_data property later
                        pass
            
            # Skip writing if in skipped stack
            if not skip_node_stack:
                out_lines.append(line)
            continue
            
        # Parse Connections/Editables (which are at the end, not under [node])
        if line.startswith('[connection ') or line.startswith('[editable '):
            # We don't want connections of deleted nodes
            continue
            
        # If we are currently inside a skipped node branch, skip properties as well
        if skip_node_stack:
            # Check if we encounter properties/variables. We don't write them.
            continue
            
        # For the allowed nodes, clean up some properties:
        # 1. Clear tile map data on TileMapLayer to make it blank
        if line_stripped.startswith('tile_map_data ='):
            continue
            
        # 2. Reset player spawn/start positions to defaults in the tscn
        if current_node_name == "Player1" and line_stripped.startswith('position ='):
            line = 'position = Vector2(250, 400)\n'
        if current_node_name == "Player2" and line_stripped.startswith('position ='):
            line = 'position = Vector2(400, 400)\n'
            
        out_lines.append(line)
        
    with open(output_path, "w", encoding="utf-8") as f:
        f.writelines(out_lines)
    print("Base level scene generated successfully!")

if __name__ == "__main__":
    create_base_level()
