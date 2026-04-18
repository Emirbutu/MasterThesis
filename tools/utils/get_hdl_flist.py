# Copyright 2025 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

from parsers import ParserClass

parser = ParserClass()
file_list = []
vars_dict = {}


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _expand_value(token: str) -> list[str]:
    token = _strip_quotes(token)
    if token == '':
        return []
    if token.startswith('{*}$'):
        var_name = token[4:]
        raw_value = vars_dict.get(var_name, '')
        expanded = _strip_quotes(raw_value)
        return [item for item in expanded.split() if item]
    for var_name, raw_value in vars_dict.items():
        token = token.replace('${' + var_name + '}', _strip_quotes(raw_value))
    return [token] if token else []

with open(parser.args.file, 'r') as file:
    IN_FILE_LIST = False
    IN_VAR_LIST = False
    current_var_name = ''
    current_var_items = []
    for line in file:
        stripped = line.strip()

        if IN_VAR_LIST:
            if stripped.startswith(']'):
                vars_dict[current_var_name] = ' '.join(current_var_items)
                IN_VAR_LIST = False
                current_var_name = ''
                current_var_items = []
            else:
                for token in stripped.split():
                    token = token.strip('"')
                    if token and token != '\\':
                        current_var_items.append(token)
            continue

        if stripped.startswith('set HDL_FILES'):
            IN_FILE_LIST = True
            continue
        elif stripped.startswith(']'):
            IN_FILE_LIST = False
        elif stripped.startswith('set'):
            parts = stripped.split(maxsplit=2)
            if len(parts) >= 3:
                vars_dict[parts[1]] = parts[2]
                if parts[2].startswith('[ list'):
                    IN_VAR_LIST = True
                    current_var_name = parts[1]
                    current_var_items = []
                    continue

        if IN_FILE_LIST:
            for token in stripped.split():
                if token in {'set', '[', 'list', '\\', 'set', 'HDL_FILES', ']'}:
                    continue
                file_list.extend(_expand_value(token))

# Substitute variables ${VARS} in file_list with values from vars_dict
exp_file_list = []
for file in file_list:
    expanded = file
    for var in vars_dict.keys():
        if '${' + var + '}' in expanded:
            expanded = expanded.replace('${' + var + '}', _strip_quotes(vars_dict[var]))
    if expanded:
        exp_file_list.append(expanded)

file_list_str = ' '.join(exp_file_list)

print(file_list_str)
