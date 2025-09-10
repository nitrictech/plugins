#!/usr/bin/env python3
"""
Generate plugin documentation from manifest files.
"""

import os
import yaml
import re
from pathlib import Path
from typing import Dict, Any, List, Optional
from dataclasses import dataclass

# Configuration
PLUGINS_DIR = os.getenv("PLUGINS_DIR")
if not PLUGINS_DIR:
    raise ValueError("PLUGINS_DIR environment variable is required")

DOCS_DIR = os.getenv("DOCS_DIR")
if not DOCS_DIR:
    raise ValueError("DOCS_DIR environment variable is required")

PROVIDERS = ["aws", "gcp", "neon"]


@dataclass
class PluginInput:
    name: str
    type: str
    required: bool = False
    description: str = ""
    example: str = ""
    default: Optional[str] = None


@dataclass
class PluginOutput:
    name: str
    type: str
    description: str = ""
    example: str = ""


@dataclass
class Plugin:
    name: str
    type: str
    title: str
    description: str
    inputs: List[PluginInput]
    outputs: List[PluginOutput]


class PluginDocGenerator:
    def __init__(self, plugins_dir: str, docs_dir: str):
        self.plugins_dir = Path(plugins_dir)
        self.docs_dir = Path(docs_dir)
        
    def generate_all(self):
        """Generate documentation for all plugins."""
        for provider in PROVIDERS:
            provider_dir = self.plugins_dir / provider
            if not provider_dir.exists():
                continue
                
            print(f"Processing {provider}...")
            self._process_provider(provider, provider_dir)
        
        print("Plugin documentation generation completed!")
    
    def _process_provider(self, provider: str, provider_dir: Path):
        """Process all plugins for a provider."""
        provider_docs_dir = self.docs_dir / provider
        provider_docs_dir.mkdir(parents=True, exist_ok=True)
        
        for manifest_path in provider_dir.rglob("manifest.yaml"):
            plugin_dir = manifest_path.parent
            plugin_name = plugin_dir.name
            
            # Skip if this is the provider root
            if plugin_name == provider:
                continue
                
            try:
                plugin = self._load_plugin(plugin_dir, provider, plugin_name)
                doc_content = self._generate_doc(plugin)
                
                output_file = provider_docs_dir / f"{plugin_name}.mdx"
                output_file.write_text(doc_content)
                print(f"Generated: {output_file}")
                
            except Exception as e:
                print(f"Error processing {provider}/{plugin_name}: {e}")
    
    def _load_plugin(self, plugin_dir: Path, provider: str, plugin_name: str) -> Plugin:
        """Load plugin data from manifest and terraform files."""
        # Load manifest
        manifest_path = plugin_dir / "manifest.yaml"
        with open(manifest_path) as f:
            manifest_data = yaml.safe_load(f)
        
        # Load terraform variables for defaults
        terraform_vars = self._load_terraform_variables(plugin_dir / "module" / "variables.tf")
        
        # Process inputs
        inputs = []
        inputs_data = manifest_data.get("inputs", {}) or {}
        for name, input_data in inputs_data.items():
            tf_var = terraform_vars.get(name, {})
            
            # Get description (manifest first, then terraform)
            description = input_data.get("description", "") or tf_var.get("description", "")
            
            # Get default (terraform first, then manifest)
            default = None
            if tf_var.get("default") is not None:
                default = str(tf_var["default"])
            elif input_data.get("default") is not None:
                default = str(input_data["default"])
            
            inputs.append(PluginInput(
                name=name,
                type=input_data.get("type", "string"),
                required=input_data.get("required", False),
                description=description,
                example=input_data.get("example", ""),
                default=default
            ))
        
        # Sort inputs by name
        inputs.sort(key=lambda x: x.name)
        
        # Process outputs
        outputs = []
        outputs_data = manifest_data.get("outputs", {}) or {}
        for name, output_data in outputs_data.items():
            outputs.append(PluginOutput(
                name=name,
                type=output_data.get("type", "string"),
                description=output_data.get("description", ""),
                example=output_data.get("example", "")
            ))
        
        # Sort outputs by name
        outputs.sort(key=lambda x: x.name)
        
        # Use display_name if available, otherwise generate title
        display_name = manifest_data.get("display_name")
        title = display_name if display_name else self._generate_title(plugin_name, provider)
        
        return Plugin(
            name=plugin_name,
            type=manifest_data.get("type", ""),
            title=title,
            description=manifest_data.get("description", self._generate_description(manifest_data, provider)),
            inputs=inputs,
            outputs=outputs
        )
    
    def _load_terraform_variables(self, variables_file: Path) -> Dict[str, Dict[str, Any]]:
        """Parse terraform variables.tf file for defaults and descriptions."""
        if not variables_file.exists():
            return {}
        
        variables = {}
        content = variables_file.read_text()
        
        # Find variable blocks using regex
        var_pattern = r'variable\s+"([^"]+)"\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}'
        
        for match in re.finditer(var_pattern, content, re.MULTILINE | re.DOTALL):
            var_name = match.group(1)
            var_content = match.group(2)
            
            var_info = {}
            
            # Extract description
            desc_match = re.search(r'description\s*=\s*"([^"]*)"', var_content)
            if desc_match:
                var_info["description"] = desc_match.group(1)
            
            # Extract default (simple values only)
            default_match = re.search(r'default\s*=\s*([^\n}]+)', var_content)
            if default_match:
                default_value = default_match.group(1).strip()
                # Remove quotes and clean up
                if default_value.startswith('"') and default_value.endswith('"'):
                    var_info["default"] = default_value[1:-1]
                elif default_value in ["true", "false"]:
                    var_info["default"] = default_value
                elif default_value.replace(".", "").isdigit():
                    var_info["default"] = default_value
                elif default_value == "null":
                    var_info["default"] = None
            
            variables[var_name] = var_info
        
        return variables
    
    def _generate_title(self, plugin_name: str, provider: str) -> str:
        """Generate a clean title from plugin name."""
        title = plugin_name.replace("-", " ").title()
        
        # Remove provider prefix
        if provider == "aws":
            title = title.replace("Aws ", "")
        elif provider == "gcp":
            title = title.replace("Gcp ", "")
        
        return title
    
    def _generate_description(self, manifest_data: Dict[str, Any], provider: str) -> str:
        """Generate fallback description if no description is provided in manifest."""
        plugin_type = manifest_data.get("type", "")
        return f"{plugin_type.title()} component for {provider}"
    
    def _generate_doc(self, plugin: Plugin) -> str:
        """Generate MDX documentation for a plugin."""
        doc_lines = [
            "---",
            f"title: {plugin.title}",
            f"description: {plugin.description}",
            "---",
            ""
        ]
        
        if plugin.inputs:
            doc_lines.extend([
                "## Configuration",
                ""
            ])
            
            for input_field in plugin.inputs:
                doc_lines.extend(self._format_input_field(input_field))
        
        
        if plugin.outputs:
            doc_lines.extend([
                "## Outputs",
                ""
            ])
            for output in plugin.outputs:
                doc_lines.extend(self._format_output_field(output))
        
        return "\n".join(doc_lines)
    
    def _format_input_field(self, input_field: PluginInput) -> List[str]:
        """Format a single input field as ParamField."""
        param_attrs = [f'path="{input_field.name}"', f'type="{input_field.type}"']
        
        if input_field.required:
            param_attrs.append("required")
        
        if input_field.default:
            param_attrs.append(f'default="{input_field.default}"')
        
        lines = [
            f"<ParamField {' '.join(param_attrs)}>",
            f"  {input_field.description}"
        ]
        
        if input_field.example:
            # Format all examples with backticks for consistent code formatting
            example = str(input_field.example)
            example = f"`{example}`"
            
            lines.extend([
                "  ",
                f"  **Example:** {example}"
            ])
        
        lines.extend([
            "</ParamField>",
            ""
        ])
        
        return lines
    
    def _format_output_field(self, output: PluginOutput) -> List[str]:
        """Format a single output field as ResponseField."""
        lines = [
            f'<ResponseField name="{output.name}" type="{output.type}">',
            f"  {output.description}"
        ]
        
        if output.example:
            # Format all examples with backticks for consistent code formatting
            example = str(output.example)
            example = f"`{example}`"
            
            lines.extend([
                "  ",
                f"  **Example:** {example}"
            ])
        
        lines.extend([
            "</ResponseField>",
            ""
        ])
        
        return lines


def main():
    """Main entry point."""
    generator = PluginDocGenerator(PLUGINS_DIR, DOCS_DIR)
    generator.generate_all()


if __name__ == "__main__":
    main()