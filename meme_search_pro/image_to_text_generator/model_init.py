import os
from transformers import AutoModelForCausalLM, AutoTokenizer
import logging
logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s"
)

# define cache location
cache_dir = "/models"

# create cache directory if it doesn't exist
if not os.path.exists(cache_dir):
    os.makedirs(cache_dir)

# set hf cache env variable to cache directory
os.environ["HF_HOME"] = cache_dir


def download_moondream():
    # model identifiers
    model_id = "vikhyatk/moondream2"
    revision = "2024-08-26"

    # instantiate model and tokenizer
    logging.info("INFO: instantiating model...")
    model = AutoModelForCausalLM.from_pretrained(
        model_id, trust_remote_code=True, revision=revision
    )
    logging.info("INFO:... complete")
    logging.info("INFO: instantiating tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(model_id, revision=revision)
    logging.info("...complete")
    return model, tokenizer