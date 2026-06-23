from pydantic import BaseModel, field_validator
from constants import available_models, default_model


# model for received jobs
class JobModel(BaseModel):
    image_core_id: int
    image_path: str
    attempt_id: int
    callback_token: str
    model: str = default_model

    @field_validator("model")
    @classmethod
    def validate_option(cls, value: str) -> str:
        if value is not None and value not in available_models:
            raise ValueError(f"model must be one of {available_models}")
        return value
