#!/usr/bin/env python3
"""
Post-synthesis netlist modifier: inject cdeFileInit parameters into SRAM instances.

This script parses a synthesized Verilog netlist and injects the correct CDE file
initialization parameters into TS1N28HPCPUHDHVTB64X256M1SWBSO SRAM macro instances.

The CDE filenames are hex-encoded in the tc_sram_syn module names during synthesis.
This script extracts them and adds the .cdeFileInit parameter to each SRAM instance.

Usage:
    python3 inject_cde_init.py <input_netlist> <output_netlist>
"""

import re
import sys
from pathlib import Path


def extract_hex_filename(hex_str):
    """
    Decode a hex string to get the original filename.
    Format: <length>h<hex_data> e.g., "952h2f75736572732f..."
    """
    # Extract length and hex data
    match = re.match(r'(\d+)h(.+)', hex_str)
    if not match:
        return None
    
    length, hex_data = match.groups()
    try:
        # Convert hex string to bytes, then to ASCII
        filename = bytes.fromhex(hex_data).decode('ascii')
        return filename
    except (ValueError, UnicodeDecodeError) as e:
        print(f"Error decoding hex: {hex_str}: {e}", file=sys.stderr)
        return None


def extract_cde_params_from_module_names(netlist_text):
    """
    Find all tc_sram_syn module names and extract their CDE file parameters.
    Handles multi-line module declarations.
    
    Returns a dict mapping module names to their CDE filenames.
    """
    cde_map = {}
    
    # Pattern to match tc_sram_syn module definitions with CdeFileInit parameter in module name
    # Module name format: tc_sram_syn_NumWords...CdeFileInit<hex>(...)
    # Handle newlines that may appear in the declaration
    pattern = r'module\s+tc_sram_syn_[^\(]+CdeFileInit(\d+h[0-9a-fA-F]+)[^\(]*\('
    
    for match in re.finditer(pattern, netlist_text, re.MULTILINE | re.DOTALL):
        hex_encoded = match.group(1)
        filename = extract_hex_filename(hex_encoded)
        if filename:
            # Extract the full module name from the match
            full_text = match.group(0)
            # Find the module name between "module" and "("
            module_match = re.search(r'module\s+(tc_sram_syn_[^\(]+CdeFileInit\d+h[0-9a-fA-F]+)', full_text)
            if module_match:
                full_module_name = module_match.group(1).replace('\n', '')
                cde_map[full_module_name] = filename
    
    return cde_map


def make_flexible_regex(text):
    """Match text across arbitrary whitespace and line breaks."""
    return r'\s*'.join(re.escape(char) for char in text)


def process_netlist(input_file, output_file):
    """
    Process the netlist: extract CDE parameters and inject them into SRAM instances.
    Strategy: match each tc_sram_syn module block directly, then patch the SRAM instance
    inside that block with the corresponding CDE file.
    """
    print(f"Reading netlist from {input_file}...", file=sys.stderr)
    with open(input_file, 'r', encoding='utf-8', errors='replace') as f:
        netlist_text = f.read()
    
    print("Extracting CDE file parameters from module names...", file=sys.stderr)
    cde_map = extract_cde_params_from_module_names(netlist_text)
    
    print(f"Found {len(cde_map)} SRAM modules with CDE parameters:", file=sys.stderr)
    for module_name, cde_file in sorted(cde_map.items()):
        short_name = module_name[-80:] if len(module_name) > 80 else module_name
        print(f"  ...{short_name}: {cde_file}", file=sys.stderr)
    
    if len(cde_map) == 0:
        print("ERROR: No CDE parameters found!", file=sys.stderr)
        sys.exit(1)
    
    modified_text = netlist_text
    injection_count = 0
    
    for module_name, cde_file in sorted(cde_map.items()):
        module_pattern = re.compile(
            r'(module\s+' + make_flexible_regex(module_name) + r'\s*\(.*?endmodule)',
            re.DOTALL,
        )
        module_match = module_pattern.search(modified_text)

        if not module_match:
            print(f"  WARNING: Could not find module {module_name}", file=sys.stderr)
            continue

        module_block = module_match.group(1)
        sram_pattern = re.compile(
            r'(TS1N28HPCPUHDHVTB64X256M1SWBSO\s+)(gen_64x256_i_sp_ram\s*\(.*?\)\s*;)',
            re.DOTALL,
        )
        sram_match = sram_pattern.search(module_block)

        if not sram_match:
            print(f"  WARNING: No SRAM instance found in {module_name}", file=sys.stderr)
            continue

        sram_prefix = sram_match.group(1)
        sram_instance = sram_match.group(2)
        if '#(' in sram_prefix or '.cdeFileInit(' in sram_instance:
            print(f"  WARNING: SRAM instance in {module_name} already has cdeFileInit", file=sys.stderr)
            continue

        cde_filename = Path(cde_file).name
        sram_injected = f'{sram_prefix}#(\n                .cdeFileInit("{cde_filename}")\n            ) {sram_instance}'
        modified_block = module_block[:sram_match.start(1)] + sram_injected + module_block[sram_match.end(2):]
        modified_text = modified_text[:module_match.start(1)] + modified_block + modified_text[module_match.end(1):]
        injection_count += 1
        print(f"  Injected {cde_file}", file=sys.stderr)
    
    print(f"Total injected: {injection_count} cdeFileInit parameters", file=sys.stderr)
    
    print(f"Writing modified netlist to {output_file}...", file=sys.stderr)
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(modified_text)
    
    print("Done!", file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: inject_cde_init.py <input_netlist> <output_netlist>", file=sys.stderr)
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    if not Path(input_file).exists():
        print(f"ERROR: Input file not found: {input_file}", file=sys.stderr)
        sys.exit(1)
    
    process_netlist(input_file, output_file)
