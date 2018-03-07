from typing import Dict, List

from docker.types import Mount

from containers import Containers
from images import Images
from instances.instance_base import Instance
from volumes import Volumes, VolumeFile


class SimpleInstance(Instance):
    def __init__(self,
                 images: Images,
                 containers: Containers,
                 volumes: Volumes,
                 execution_id: str):
        self.images = images
        self.containers = containers
        self.volumes = volumes
        self.execution_id = execution_id

    def run(self, command: List[str], snapshot_id: str, files: Dict[str, str]):
        volume = self.volumes.create(self.volume_name, {
            path: VolumeFile(contents) for path, contents in files.items()
        })
        self.containers.run(name=self.execution_id,
                            tag=snapshot_id,
                            command=command,
                            mounts=[Mount(source=volume.name,
                                          target=Volumes.VOLUME_MOUNT)])

    def logs(self, stdout: bool = True, stderr: bool = True):
        return self.containers.logs(self.execution_id,
                                    stdout=stdout,
                                    stderr=stderr)

    def cleanup(self):
        self.containers.rm(self.execution_id)
        self.volumes.remove(self.volume_name)

    @property
    def volume_name(self):
        return f'batman-{self.execution_id}'
