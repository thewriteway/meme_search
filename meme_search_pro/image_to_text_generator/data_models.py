from pydantic import BaseModel


# model for received jobs
class JobModel(BaseModel):
    image_core_id: int
    image_path: str

