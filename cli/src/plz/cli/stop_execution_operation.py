from typing import Optional

import requests

from plz.cli.configuration import Configuration
from plz.cli.log import log_info
from plz.cli.operation import Operation, check_status


class StopExecutionOperation(Operation):
    @staticmethod
    def prepare_argument_parser(parser, args):
        if len(args) > 1:
            # Execution ID was specified
            parser.add_argument(dest='execution_id')

    def __init__(self, configuration: Configuration,
                 execution_id: Optional[str] = None):
        super().__init__(configuration)
        self.execution_id = execution_id

    def run(self):
        response = requests.delete(
            self.url('executions', self.get_execution_id()),
            args={'fail_if_deleted': True})
        check_status(response, requests.codes.ok)
        if response.status_code == requests.codes.expectation_failed:
            # Returned when already deleted
            log_info('Process already stopped')
        else:
            check_status(response, requests.codes.no_content)
            log_info('Stopped')
