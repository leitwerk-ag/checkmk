# generated by datamodel-codegen:
#   filename:  vue_formspec_components.json
#   timestamp: 2024-05-23T12:11:53+00:00

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, List, Optional, Union

from cmk.gui.form_specs.vue.type_defs.vue_validators import VueValidators


@dataclass
class VueBase:
    title: str = ""
    help: str = ""
    validators: list[VueValidators] = field(default_factory=list)


@dataclass
class VueInteger(VueBase):
    vue_type: str = "integer"
    label: Optional[str] = None
    unit: Optional[str] = None


@dataclass
class VueFloat(VueBase):
    vue_type: str = "float"
    label: Optional[str] = None
    unit: Optional[str] = None


@dataclass
class VueLegacyValuespec(VueBase):
    vue_type: str = "legacy_valuespec"


@dataclass
class VueString(VueBase):
    vue_type: str = "string"
    placeholder: Optional[str] = None


@dataclass
class Model:
    all_schemas: Optional[List[VueSchema]] = None


@dataclass
class VueDictionaryElement:
    ident: str
    required: bool
    default_value: Any
    vue_schema: VueSchema


@dataclass
class VueDictionary(VueBase):
    vue_type: str = "dictionary"
    elements: List[VueDictionaryElement] = field(default_factory=list)


@dataclass
class VueSingleChoiceElement:
    name: str = ""
    title: str = ""


@dataclass
class VueSingleChoice(VueBase):
    vue_type: str = "single_choice"
    elements: list[VueSingleChoiceElement] = field(default_factory=list)
    no_elements_text: Optional[str] = None
    frozen: bool = False
    label: Optional[str] = None


@dataclass
class VueCascadingSingleChoiceElement:
    name: str
    title: str
    default_value: Any
    parameter_form: VueBase


@dataclass
class VueCascadingSingleChoice(VueBase):
    vue_type: str = "cascading_single_choice"
    elements: list[VueCascadingSingleChoiceElement] = field(default_factory=list)
    no_elements_text: Optional[str] = None
    frozen: bool = False
    label: Optional[str] = None


@dataclass
class VueList(VueBase):
    editable_order: bool = True
    vue_type: str = "list"
    element_template: VueBase = field(default_factory=VueBase)
    element_default_value: Any = None
    add_element_label: str = ""
    remove_element_label: str = ""
    no_element_label: str = ""


VueSchema = Union[
    VueInteger,
    VueFloat,
    VueString,
    VueDictionary,
    VueSingleChoice,
    VueList,
    VueLegacyValuespec,
    VueCascadingSingleChoice,
]
