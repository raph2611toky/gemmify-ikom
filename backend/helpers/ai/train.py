from unsloth import FastLanguageModel
import torch
from trl import SFTTrainer, SFTConfig
from datasets import load_dataset

MODEL_NAME = "unsloth/gemma-4-E2B-it-unsloth-bnb-4bit"

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name = MODEL_NAME,
    max_seq_length = 4096,
    load_in_4bit = True,
    dtype = None,
    device_map = {"": 0}, 
)

model = FastLanguageModel.get_peft_model(
    model,
    r = 16,
    target_modules = ["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"],
    lora_alpha = 16,
    lora_dropout = 0,
    bias = "none",
    use_gradient_checkpointing = "unsloth",
    random_state = 20260723,
)

DATA_DIR = "datasets"  
dataset = load_dataset(
    "json",
    data_files={
        "train": f"{DATA_DIR}/mpanabe_train.jsonl",
        "validation": f"{DATA_DIR}/mpanabe_validation.jsonl",
        "test": f"{DATA_DIR}/mpanabe_test.jsonl",
    }
)

# dans collab: 
# from google.colab import files
# uploaded = files.upload()

print(dataset)
print(dataset["train"][0])

def is_text_only(example):
    return example.get("modality", "text") == "text"

dataset = dataset.filter(is_text_only)

def format_chat(example):
    text = tokenizer.apply_chat_template(
        example["messages"],
        tokenize=False,
        add_generation_prompt=False,
    )
    return {"text": text}

dataset = dataset.map(
    format_chat,
    remove_columns=[c for c in dataset["train"].column_names if c != "text"]
)

print(dataset["train"][0]["text"][:500])

training_args = SFTConfig(
    per_device_train_batch_size = 4,      
    per_device_eval_batch_size = 4,
    gradient_accumulation_steps = 4,
    warmup_steps = 30,
    num_train_epochs = 3,
    learning_rate = 2e-4,
    logging_steps = 10,
    eval_strategy = "steps",
    eval_steps = 100,
    save_strategy = "steps",
    save_steps = 200,
    save_total_limit = 2,
    optim = "adamw_8bit",
    weight_decay = 0.01,
    lr_scheduler_type = "cosine",
    seed = 20260723,
    output_dir = "/kaggle/working/outputs",
    max_seq_length = 4096,
    dataset_text_field = "text",
    report_to = "none",
)

trainer = SFTTrainer(
    model = model,
    tokenizer = tokenizer,
    train_dataset = dataset["train"],
    eval_dataset = dataset["validation"],
    args = training_args,
)

trainer.train()