#!/usr/bin/env python3
# Copyright (C) 2019 Checkmk GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.
"""
This special agent is deprecated. Please use netapp_ontap_ports.
"""

from collections.abc import Container, Mapping

from cmk.agent_based.v2 import (
    AgentSection,
    CheckPlugin,
    CheckResult,
    DiscoveryResult,
    Result,
    Service,
    State,
    StringTable,
)
from cmk.plugins.lib import netapp_api


def port_name(name: str, values: Mapping[str, str]) -> str:
    try:
        return "{} port {}".format(values["port-type"].capitalize(), name)
    except KeyError:
        return name


def parse_netapp_api_ports(string_table: StringTable) -> netapp_api.SectionSingleInstance:
    return netapp_api.parse_netapp_api_single_instance(
        string_table, custom_keys=None, item_func=port_name
    )


agent_section_netapp_api_ports = AgentSection(
    name="netapp_api_ports",
    parse_function=parse_netapp_api_ports,
)


def discover_netapp_api_ports(
    params: Mapping[str, Container[str]],
    section: netapp_api.SectionSingleInstance,
) -> DiscoveryResult:
    ignored_ports = params["ignored_ports"]
    for item, values in section.items():
        if values.get("port-type") in ignored_ports:
            continue
        if "health-status" in values:
            yield Service(item=item)


def check_netapp_api_ports(
    item: str,
    section: netapp_api.SectionSingleInstance,
) -> CheckResult:
    if (data := section.get(item)) is None:
        return

    health_state = data.get("health-status", "unknown")
    yield Result(
        state={"healthy": State.OK, "unknown": State.UNKNOWN}.get(health_state, State.CRIT),
        summary=f"Health status: {health_state}",
    )
    yield Result(
        state=State.OK,
        summary="Operational speed: %s" % data.get("operational-speed", "undetermined"),
    )


check_plugin_netapp_api_ports = CheckPlugin(
    name="netapp_api_ports",
    service_name="%s",
    discovery_function=discover_netapp_api_ports,
    discovery_ruleset_name="discovery_netapp_api_ports_ignored",
    discovery_default_parameters={"ignored_ports": []},
    check_function=check_netapp_api_ports,
)
