#!/usr/bin/env python3
# Copyright (C) 2019 Checkmk GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.

# <<<veeam_jobs:sep(9) >>>
# BACKUP_RIS      Backup  Stopped Success 27.10.2013 22:00:17     27.10.2013 22:06:12
# BACKUP_R43-local_HXWH44 Backup  Stopped Success 26.10.2013 18:00:20     26.10.2013 18:46:03
# BACKUP_R43-Pool4_HXWH44 Backup  Stopped Failed  26.10.2013 23:13:13     27.10.2013 00:51:17
# BACKUP_R43-Pool3_HXWH44 Backup  Stopped Failed  27.10.2013 02:59:29     27.10.2013 08:59:51
# REPL_KNESXIDMZ  Replica Stopped Success 27.10.2013 44:00:01     27.10.2013 44:44:26
# BACKUP_KNESXI   Backup  Stopped Success 28.10.2013 05:00:04     28.10.2013 05:32:15
# BACKUP_KNESXit  Backup  Stopped Success 26.10.2013 22:30:02     27.10.2013 02:37:30
# BACKUP_R43-Pool5_HXWH44 Backup  Stopped Success 27.10.2013 23:00:00     27.10.2013 23:04:53
# BACKUP_R43-Pool2_HXWH44 Backup  Stopped Failed  27.10.2013 02:37:45     27.10.2013 02:45:35

from datetime import datetime

from cmk.base.check_api import check_levels, LegacyCheckDefinition
from cmk.base.config import check_info

from cmk.agent_based.v2 import StringTable, render

_DAY = 3600 * 24


def inventory_veeam_jobs(info):
    return [(x[0], None) for x in info]


def check_veeam_jobs(item, params, info):
    for line in info:
        if len(line) < 7:
            continue  # Skip incomplete lines

        job_name, job_type, job_last_state, job_last_result, job_creation_time, job_end_time, last_scheduled_job_date = line[
            :7
        ]

        job_creation_time = datetime.strptime(job_creation_time, "%d.%m.%Y %H:%M:%S")
        job_end_time = datetime.strptime(job_end_time, "%d.%m.%Y %H:%M:%S")
        last_scheduled_job_date = datetime.strptime(last_scheduled_job_date, "%d.%m.%Y %H:%M:%S")

        if job_name != item:
            continue  # Skip not matching lines

        if job_last_state in ["Starting", "Working", "Postprocessing"]:
            return 0, "Running since {} (current state is: {})".format(
                job_creation_time,
                job_last_state,
            )

        if job_last_result == "Success":
            state = 0
        elif job_last_state == "Idle" and job_type == "BackupSync":
            # A sync job is always idle
            state = 0
        elif job_last_result == "Failed":
            state = 2
        elif job_last_state == "Stopped" and job_last_result == "Warning":
            state = 1
        else:
            state = 3

        yield state, "State: {}, Result: {}, Creation time: {}, End time: {}, Type: {}".format(
            job_last_state,
            job_last_result,
            job_creation_time,
            job_end_time,
            job_type,
        )

        time_diff = (last_scheduled_job_date - job_creation_time).total_seconds()
        yield check_levels(
            time_diff,
            None,
            params["levels_upper_time_since_last_job"],
            human_readable_func=render.timespan,
            infoname="Time since last run should have been executed",
        )


def parse_veeam_jobs(string_table: StringTable) -> StringTable:
    return string_table


check_info["veeam_jobs"] = LegacyCheckDefinition(
    parse_function=parse_veeam_jobs,
    service_name="VEEAM Job %s",
    discovery_function=inventory_veeam_jobs,
    check_function=check_veeam_jobs,
    check_default_parameters={
        "levels_upper_time_since_last_job": (1 * _DAY, 2 * _DAY),
    },
)
