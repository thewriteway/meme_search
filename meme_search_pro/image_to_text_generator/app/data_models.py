from pydantic import BaseModel, validator
from constants import available_models, default_model


# model for received jobs
class JobModel(BaseModel):
    image_core_id: int
    image_path: str
    model: str = default_model

    @validator("model")
    def validate_option(cls, value):
        if value is not None and value not in available_models:
            raise ValueError(f"model must be one of {available_models}")
        return value
