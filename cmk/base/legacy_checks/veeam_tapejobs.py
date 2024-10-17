#!/usr/bin/env python3
# Copyright (C) 2019 Checkmk GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.


import time

from cmk.base.check_api import check_levels, LegacyCheckDefinition
from cmk.base.config import check_info

from cmk.agent_based.v2 import get_value_store, render

BACKUP_STATE = {"Success": 0, "Warning": 1, "Failed": 2}

_DAY = 3600 * 24


def parse_veeam_tapejobs(string_table):
    parsed = {}
    columns = [s.lower() for s in string_table[0]]

    for line in string_table[1:]:
        if len(line) < len(columns):
            continue

        name = " ".join(line[: -(len(columns) - 1)])
        job_id, last_result, last_state, creation_time, end_time = line[-(len(columns) - 1):]
        parsed[name] = {
            "job_id": job_id,
            "last_result": last_result,
            "last_state": last_state,
            "creation_time": creation_time,
            "end_time": end_time,
        }

    return parsed


def inventory_veeam_tapejobs(parsed):
    for job in parsed:
        yield job, {}


def check_veeam_tapejobs(item, params, parsed):
    if not (data := parsed.get(item)):
        return

    value_store = get_value_store()
    job_id = data["job_id"]
    last_result = data["last_result"]
    last_state = data["last_state"]
    creation_time = data["creation_time"]
    end_time = data["end_time"]

    # handle currently running jobs
    if last_result == "None" and last_state in ("Working", "Idle"):
        running_since = value_store.get(f"{job_id}.running_since")
        now = time.time()
        if not running_since:
            running_since = now
            value_store[f"{job_id}.running_since"] = now
        running_time = now - running_since

        yield 0, "Backup in progress since {} (currently {})".format(
            render.datetime(running_since),
            last_state.lower(),
        )
        yield check_levels(
            running_time,
            None,
            params["levels_upper"],
            human_readable_func=render.timespan,
            infoname="Running time",
        )
        return

    # calculate check state
    state = BACKUP_STATE.get(last_result, 2)

    # update value store
    value_store[f"{job_id}.running_since"] = None
    if state == 0:
        value_store[f"{job_id}.last_ok_creation_time"] = creation_time
        value_store[f"{job_id}.last_ok_end_time"] = end_time

    # generate output
    yield state, "State: {}, Result: {}, Creation time: {}, End time: {}".format(
        last_state,
        last_result,
        creation_time,
        end_time,
    )
    yield 0, "Last Sucesfull Job: Creation time: {}, End time: {}".format(
        value_store.get(f"{job_id}.last_ok_creation_time"),
        value_store.get(f"{job_id}.last_ok_end_time"),
    )


check_info["veeam_tapejobs"] = LegacyCheckDefinition(
    parse_function=parse_veeam_tapejobs,
    service_name="VEEAM Tape Job %s",
    discovery_function=inventory_veeam_tapejobs,
    check_function=check_veeam_tapejobs,
    check_ruleset_name="veeam_tapejobs",
    check_default_parameters={
        "levels_upper": (1 * _DAY, 2 * _DAY),
    },
)
