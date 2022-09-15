#!/usr/bin/env python
# -*- coding: utf-8 -*-

# STD
from datetime import datetime, timedelta
import pytz
import shelve

now=datetime.now(tz=pytz.utc)

# Name of the file used by PersistentScheduler to store the last run times of periodic tasks. 
file_data=shelve.open('/tmp/celerybeat-schedule', flag='r')

for task_name, task in file_data['entries'].items():
	try:
		if hasattr(task.schedule, "run_every"):
			assert now<(task.last_run_at+task.schedule.run_every)
		else:
			#print(task.schedule.is_due(task.last_run_at))
			#print(task.last_run_at)
			assert 0<(task.schedule.is_due(task.last_run_at)[1])
	except AttributeError:
		assert timedelta()<task.schedule.remaining_estimate(task.last_run_at)

