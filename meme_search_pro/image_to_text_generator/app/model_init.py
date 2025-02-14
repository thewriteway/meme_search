from PIL import Image
import torch
from transformers import AutoModelForCausalLM, AutoModelForVision2Seq, AutoProcessor
from transformers.image_utils import load_image
from constants import available_models
from log_config import logging 


# Automatically determine the best available device
if torch.backends.mps.is_available():
    device = "mps"  # Metal (Apple Silicon)
elif torch.cuda.is_available():
    device = "cuda"  # NVIDIA GPU
else:
    device = "cpu"  # Fallback to CPU

torch_dtype = torch.float16 if torch.cuda.is_available() else torch.float32

logging.info(f"INFO: using device: {device}")


# set model and tokenizer
model = None
tokenizer = None


class TestImageToText:
    def __init__(self):
        pass

    def download(self):
        return None

    def extract(self, image_path):
        return "this is a test"


class MoondreamImageToText:
    """
    moondream v2 is a 1.9B text-to-image model that has several great capabilities trained in.
    These include:
    - captioning (used here)
    - general querying (e.g., "how many people are in this image?")
    - object detection
    - gaze detection

    for our application we use the "short caption" functionality.
    the repo: https://huggingface.co/vikhyatk/moondream2
    """
    def __init__(self, model_id, revision):
        self.model_id = model_id
        self.revision = revision
        self.model = None
        self.tokenizer = None
        self.downloaded = False

    def download(self):
        logging.info("INFO: starting download or loading of model - moondream...")
        self.model = AutoModelForCausalLM.from_pretrained(
            "vikhyatk/moondream2",
            revision="2025-01-09",
            trust_remote_code=True,
        ).to(device)
        logging.info("INFO: ... complete")
        self.downloaded = True
        return None

    def extract(self, image_path):
        # check if downloaded
        if self.downloaded is False:
            message = "INFO: model not downloaded, downloading..."
            logging.info(message)
            self.download()
            logging.info("INFO: model downloaded, starting image processing")

        # normalize image_path to working directory
        image_path = "/app" + image_path

        # load in image
        image = Image.open(image_path)
        logging.info(f"DONE: image loaded, starting generation --> {image_path}")

        # process image
        logging.info(f"INFO: starting image to text extraction for image --> {image_path}")
        caption = self.model.caption(image, length="short")["caption"]
        logging.info("INFO: ... done")
        return caption.strip()


class Florence2ImageToText:
    """
    florence-2-large is a 0.7B text-to-image model that has several interesting capabilities trained in.
    These include:
    - captioning - with various lengths
    - general querying (e.g., "how many people are in this image?")
    - object detection
    - segmentation

    There are several smaller versions of the model as well.

    We use the medium-length captioning functionality here.

    the repo: https://huggingface.co/microsoft/Florence-2-large
    """
    def __init__(self, model_id, revision):
        self.model_id = model_id
        self.revision = revision
        self.model = None
        self.processor = None
        self.downloaded = False

    def download(self):
        logging.info("INFO: starting download or loading of model - florence 2...")
        self.model = AutoModelForCausalLM.from_pretrained("microsoft/Florence-2-large", torch_dtype=torch_dtype, trust_remote_code=True).to(device)
        self.processor = AutoProcessor.from_pretrained("microsoft/Florence-2-large", trust_remote_code=True)
        logging.info("INFO: ... done")
        self.downloaded = True
        return None

    def extract(self, image_path):
        # check if downloaded
        if self.downloaded is False:
            message = "INFO: model not downloaded, downloading..."
            logging.info(message)
            self.download()
            logging.info("INFO: model downloaded, starting image processing")

        # normalize image_path to working directory
        image_path = "/app" + image_path

        # load in image
        logging.info(f"INFO: starting image to text extraction for image {image_path}...")
        image = Image.open(image_path)
        task = "<DETAILED_CAPTION>"
        inputs = self.processor(text=task, images=image, return_tensors="pt").to(device, torch_dtype)
        generated_ids = self.model.generate(
            input_ids=inputs["input_ids"],
            pixel_values=inputs["pixel_values"],
            max_new_tokens=4096,
            num_beams=3,
            do_sample=False
        )
        generated_text = self.processor.batch_decode(generated_ids, skip_special_tokens=False)[0]
        parsed_answer = self.processor.post_process_generation(generated_text, task=task, image_size=(image.width, image.height))
        print("INFO: ... done")

        if '<DETAILED_CAPTION>' in parsed_answer:
            return parsed_answer['<DETAILED_CAPTION>']

        return ""


class MoondreamImageToText:
    """
    moondream v2 is a 1.9B text-to-image model that has several great capabilities trained in.
    These include:
    - captioning (used here)
    - general querying (e.g., "how many people are in this image?")
    - object detection
    - gaze detection

    for our application we use the "short caption" functionality.
    the repo: https://huggingface.co/vikhyatk/moondream2
    """
    def __init__(self, model_id, revision):
        self.model_id = model_id
        self.revision = revision
        self.model = None
        self.tokenizer = None
        self.downloaded = False

    def download(self):
        logging.info("INFO: starting download or loading of model - moondream...")
        self.model = AutoModelForCausalLM.from_pretrained(
            "vikhyatk/moondream2",
            revision="2025-01-09",
            trust_remote_code=True,
        ).to(device)
        logging.info("INFO: ... complete")
        self.downloaded = True
        return None

    def extract(self, image_path):
        # check if downloaded
        if self.downloaded is False:
            message = "INFO: model not downloaded, downloading..."
            logging.info(message)
            self.download()
            logging.info("INFO: model downloaded, starting image processing")

        # normalize image_path to working directory
        image_path = "/app" + image_path

        # load in image
        image = Image.open(image_path)
        logging.info(f"DONE: image loaded, starting generation --> {image_path}")

        # process image
        logging.info(f"INFO: starting image to text extraction for image --> {image_path}")
        caption = self.model.caption(image, length="short")["caption"]
        logging.info("INFO: ... done")
        return caption.strip()



# function to route ImageToText model based on model_name - return instance of correct model class
def model_selector(model_name: str) -> object:
    try:
        # check if model_name is valid
        if model_name not in available_models:
            error_msg = f"ERROR: choose_model failed with error: model_name {model_name} not found in model_dict"
            logging.error(error_msg)
            raise ValueError(error_msg)

        # get model_id and revision
        if model_name == "test":
            current_model = TestImageToText()
            return current_model
        else:  # current default - model = "moondream2"
            # initialize model
            current_model = MoondreamImageToText(model_id="vikhyatk/moondream2", revision="2024-08-26")

            # turn down transformers verbose logs
            # import transformers
            # transformers.logging.set_verbosity_error()

            # initialize logging
            logging.basicConfig(level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s")
            return current_model
    except Exception as e:
        error_msg = f"ERROR: choose_model failed with error: {e}"
        logging.error(error_msg)
        raise e
