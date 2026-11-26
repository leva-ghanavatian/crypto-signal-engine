from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
import your_analysis_module  # Your existing fetch + analysis code

scheduler = BlockingScheduler(timezone="Asia/Tehran")

# This trigger fires at minute 0 of every hour (12:00, 13:00, 14:00...)
trigger = CronTrigger(minute=0, timezone="Asia/Tehran")

scheduler.add_job(
    your_analysis_module.run_pipeline,  # The function that does fetch -> DB -> RSI analysis
    trigger,
    id="hourly_crypto_analysis"
)

print("Scheduler running in Asia/Tehran. Press Ctrl+C to stop.")
try:
    scheduler.start()
except (KeyboardInterrupt, SystemExit):
    pass