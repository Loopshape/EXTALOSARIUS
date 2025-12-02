#!/bin/env python3

# main_orchestrator.py

import asyncio
import hashlib
import json
import time
import sys # Import sys to access command-line arguments
from typing import Dict, Any, List
from pathlib import Path # Import pathlib

import aiohttp

# --- Configuration -----------------------------------------------------------
OLLAMA_BASE_URL = "http://localhost:11434/api/generate"

# Define a temporary directory for orchestration state
AI_TMP_DIR = Path(__file__).parent / '.ai_tmp'
AI_TMP_DIR.mkdir(parents=True, exist_ok=True) # Ensure the directory exists

# Mapping of conceptual roles to specific Ollama model names
AGENT_MODELS = {
    "cube": "cube",         # Delegator / Orchestrator
    "core": "core",         # Executor (writes code chunks)
    "loop": "loop",         # Advisor (reviews logic and plans)
    "wave": "promiser",     # Promiser (defines success criteria and goals)
    "line": "line",         # Resource Manager (manages complexity, scope)
    "coin": "coin",         # Request Securer (validates prompt integrity)
    "code": "code",         # Composer (assembles final code)
    "work": "work",         # Validator (tests/validates code chunks)
}

# --- Core Hashing Logic ------------------------------------------------------

def create_genesis_hash(prompt: str) -> str:
    """Creates the initial, immutable hash from the root prompt."""
    return hashlib.sha256(prompt.encode()).hexdigest()

def rehash_fragment(origin_hash: str, agent_name: str, thought: str) -> str:
    """Creates a new hash, linking an agent's thought to its origin."""
    fragment = f"{origin_hash}:{agent_name}:{thought}"
    return hashlib.sha256(fragment.encode()).hexdigest()

def calculate_entropy(shared_state: Dict) -> float:
    """
    Calculates a heuristic entropy score for the current shared state.
    Lower score indicates lower entropy (more coherent/stable state).
    """
    entropy_score = 0.0

    # Factor in prompt integrity (Coin agent)
    prompt_integrity = shared_state.get('prompt_integrity', '')
    if 'INTEGRITY OK' not in prompt_integrity:
        entropy_score += 0.5 # Penalty for integrity concerns

    # Factor in resource management (Line agent)
    resource_management = shared_state.get('resource_management', '')
    if 'complexity' in resource_management.lower() or 'scope' in resource_management.lower():
        if 'reduce' in resource_management.lower() or 'manage' in resource_management.lower():
            # Less penalty if management suggestions are present
            entropy_score += 0.2
        else:
            entropy_score += 0.4 # Higher penalty for unaddressed complexity/scope issues

    # Factor in plan existence and clarity (Loop agent)
    plan = shared_state.get('plan', '')
    if not plan:
        entropy_score += 1.0 # High penalty if no plan exists
    
    # Factor in code chunk validations (Work agent)
    validations = shared_state.get('validations', {})
    invalid_chunks = sum(1 for status in validations.values() if status.startswith('INVALID'))
    entropy_score += invalid_chunks * 0.7 # Penalty for each invalid chunk

    # Factor in success criteria (Wave agent)
    success_criteria = shared_state.get('success_criteria', '')
    if not success_criteria:
        entropy_score += 0.8 # Penalty if success criteria are not yet defined

    # Factor in current action stability (Cube agent) - heuristic
    current_action = shared_state.get('current_action', '')
    if current_action == "REFINE":
        entropy_score += 0.1 # Slight penalty for refinement, indicates not fully stable
    elif current_action == "PLAN" and len(shared_state.get('code_chunks', {})) > 0:
        entropy_score += 0.3 # Higher penalty if still planning after some execution

    return round(entropy_score, 2)

# --- Agent Definition --------------------------------------------------------

class Agent:
    """Represents a collaborative AI agent running on an Ollama model."""

    def __init__(self, name: str, session: aiohttp.ClientSession):
        self.name = name
        self.role = self.__class__.__name__.lower()
        self.model = AGENT_MODELS.get(self.role, "mistral") # Fallback to a default
        self.session = session

    async def reason_and_act(self, prompt: str, origin_hash: str, shared_state: Dict) -> Dict:
        """The core thinking loop of an agent."""
        start_time = time.time()
        
        # 1. Formulate the meta-prompt for the specific agent's role
        meta_prompt = self._create_meta_prompt(prompt, shared_state)
        
        # 2. Generate the reasoning fragment hash (the traceable thought)
        fragment_hash = rehash_fragment(origin_hash, self.name, meta_prompt)
        
        # 3. Call the Ollama API
        payload = {
            "model": self.model,
            "prompt": meta_prompt,
            "stream": False,  # For simplicity in this simulation
            "options": {"temperature": 0.6, "num_predict": 512}
        }
        
        response_text = ""
        try:
            async with self.session.post(OLLAMA_BASE_URL, json=payload) as response:
                response.raise_for_status()
                data = await response.json()
                response_text = data.get("response", "").strip()
        except aiohttp.ClientError as e:
            response_text = f"Error: Could not contact Ollama model '{self.model}'. {e}"

        # 4. Process the response and update the shared state
        self._process_output(response_text, shared_state)
        
        duration = time.time() - start_time
        return {
            "agent": self.name,
            "role": self.role,
            "model": self.model,
            "output": response_text,
            "reasoning_hash": fragment_hash,
            "duration_s": round(duration, 2)
        }

    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        """To be implemented by each specialized agent."""
        raise NotImplementedError

    def _process_output(self, output: str, state: Dict):
        """To be implemented by each specialized agent."""
        pass

# --- Specialized Agent Implementations --------------------------------------

class Cube(Agent): # Orchestrator
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        current_entropy = state.get('current_entropy_score', 0.0)
        status_report = f"""
Orchestration Goal: {base_prompt}
Current Action: {state.get('current_action', 'INIT')}
Current Entropy Score: {current_entropy:.2f}
Plan: {state.get('plan', 'None yet.')}
Success Criteria: {state.get('success_criteria', 'None yet.')}
Valid Chunks: {len([k for k, v in state.get('validations', {}).items() if v == 'VALID'])}
Invalid Chunks: {len([k for k, v in state.get('validations', {}).items() if v.startswith('INVALID')])}
Last Advice: {state.get('advice', 'None.')}
Prompt Integrity: {state.get('prompt_integrity', 'Not checked.')}
Resource Management: {state.get('resource_management', 'Not assessed.')}
        """
        return f"""You are 'cube', the supreme orchestrator of a multi-agent system. Your task is to analyze the current state of the project and decide the next optimal action to drive the project towards successfully achieving the 'Orchestration Goal' while minimizing the 'Current Entropy Score'.

        Based on the following status report, you must choose one of these actions: 'PLAN', 'EXECUTE', 'VALIDATE', 'REFINE', 'COMPOSE', or 'COMPLETE'.
        'COMPLETE' should only be chosen if the 'final_script' is present and seems to meet the 'Success Criteria' and 'Current Entropy Score' is low (e.g., < 0.3).

        Status Report:
        {status_report}

        Your decision MUST be a single word, representing the chosen action. Do not add any other text.
        """
    def _process_output(self, output: str, state: Dict):
        # Ensure the output is a single, valid action
        action = output.strip().upper()
        if action not in ["PLAN", "EXECUTE", "VALIDATE", "REFINE", "COMPOSE", "COMPLETE"]:
            print(f"Warning: Cube returned invalid action '{action}'. Defaulting to PLAN.")
            action = "PLAN" # Fallback
        state["current_action"] = action

class Wave(Agent): # Promiser
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        return f"""You are 'wave', the promiser. Your task is to define the success criteria for the prompt: '{base_prompt}'.
Break it down into a clear, numbered list of concise requirements. Focus on measurable and achievable criteria.
Example: 1. Script must be in Python. 2. It must achieve X. 3. It must handle error Y.
Current success criteria: {state.get('success_criteria', 'None')}. Refine if needed, otherwise re-state.
Your output MUST be ONLY the numbered list of success criteria, with no additional conversational text.
"""
    def _process_output(self, output: str, state: Dict):
        # Always update with the latest success criteria from Wave
        state['success_criteria'] = output

class Core(Agent): # Executor
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        return f"""You are 'core', the code executor. Your task is to write a single, logical chunk of Python code to help achieve the goal.
Goal: {base_prompt}
Success Criteria: {state.get('success_criteria')}
Current Code Plan: {state.get('plan')}
Existing Chunks: {list(state.get('code_chunks', {}).keys())}
Advisor's Last Remark: {state.get('advice')}
Write the next necessary code chunk. Enclose the code within ```python ... ```.
Your output MUST contain ONLY the Python code chunk, formatted strictly within ```python ... ``` tags, with no extra conversational text.
"""
    def _process_output(self, output: str, state: Dict):
        if "```python" in output:
            code_chunk = output.split("```python")[1].split("```")[0].strip()
            chunk_id = f"chunk_{len(state.get('code_chunks', {})) + 1}"
            state.setdefault('code_chunks', {})[chunk_id] = code_chunk
            state['last_chunk_id'] = chunk_id

class Work(Agent): # Validator
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        last_chunk_id = state.get('last_chunk_id', 'None')
        chunk_to_validate = state.get('code_chunks', {}).get(last_chunk_id, "No new chunk to validate.")
        return f"""You are 'work', the validator. Analyze the following Python code chunk for correctness, syntax errors, and adherence to the plan and success criteria.
Code Chunk ('{last_chunk_id}'):
{chunk_to_validate}

Success Criteria: {state.get('success_criteria')}
Respond STRICTLY with 'VALID' if it's good, or 'INVALID:' followed by a brief, actionable reason for rejection. Do not include any other text.
"""
    def _process_output(self, output: str, state: Dict):
        state.setdefault('validations', {})
        last_chunk_id = state.get('last_chunk_id')
        if last_chunk_id:
            if output.startswith("VALID"):
                state['validations'][last_chunk_id] = "VALID"
            else:
                state['validations'][last_chunk_id] = f"INVALID - {output}"
                state['advice'] = f"Validation failed for {last_chunk_id}: {output}" # Feed back to loop/core

class Loop(Agent): # Advisor
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        return f"""You are 'loop', the advisor. Review the overall plan, recent progress, and current shared state.
Goal: {base_prompt}
Plan: {state.get('plan', 'Not defined yet.')}
Validated Chunks: {[k for k, v in state.get('validations', {}).items() if v == 'VALID']}
Failed Chunks: {[k for k, v in state.get('validations', {}).items() if v.startswith('INVALID')]}
Shared State Summary: {json.dumps({k: v for k, v in state.items() if k not in ['code_chunks', 'validations']}, indent=2)}
Based on this, provide a concise, actionable next step or refinement for the plan. If no plan exists, create one. Focus on overcoming obstacles or moving towards completion.
Your output MUST be a clear, concise instruction or a refined plan.
"""
    def _process_output(self, output: str, state: Dict):
        if 'plan' not in state or 'refinement' in output.lower():
            state['plan'] = output
        state['advice'] = output

class Code(Agent): # Composer
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        return f"""You are 'code', the composer. Your task is to assemble the validated code chunks into a single, coherent, and executable Python script.
Validated Chunks:
{json.dumps({k: v for k, v in state.get('code_chunks', {}).items() if state.get('validations', {}).get(k) == 'VALID'}, indent=2)}
Success Criteria: {state.get('success_criteria')}
Ensure all necessary imports are at the top. Add appropriate function definitions and a main execution block (e.g., `if __name__ == "__main__":`). Ensure correct indentation, logical flow, and order for a fully functional script.
Enclose the final script within ```python ... ```. Your output MUST contain ONLY the Python script, formatted strictly within ```python ... ``` tags, with no extra conversational text.
"""
    def _process_output(self, output: str, state: Dict):
        if "```python" in output:
            final_script = output.split("```python")[1].split("```")[0].strip()
            state['final_script'] = final_script

class Line(Agent): # Resource Manager
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        return f"""You are 'line', the resource manager. Your task is to analyze the current state of the project, including the initial prompt and any progress made, to identify potential complexity, scope creep, or resource inefficiencies.

Current Goal: {base_prompt}
Current State: {json.dumps(state, indent=2)}

Based on this, provide a concise assessment of complexity and scope. If any issues are found, suggest specific, actionable adjustments needed to keep the project manageable and efficient. Focus on resource optimization and complexity reduction. If no issues, state 'RESOURCE MANAGEMENT OK'.
Your output MUST be a summary of complexity/scope and/or actionable suggestions, or 'RESOURCE MANAGEMENT OK'.
"""
    def _process_output(self, output: str, state: Dict):
        state['resource_management'] = output

class Coin(Agent): # Request Securer
    def _create_meta_prompt(self, base_prompt: str, state: Dict) -> str:
        return f"""You are 'coin', the request securer. Your task is to validate the integrity and safety of the initial prompt and the current shared state. Identify any ambiguities, security vulnerabilities, ethical concerns, or potential for misuse.

Initial Prompt: {base_prompt}
Current State: {json.dumps(state, indent=2)}

Based on this analysis, provide a concise integrity report. If there are concerns, list them clearly. If the prompt and state appear sound, state 'INTEGRITY OK'.
Your output MUST be a concise integrity report or 'INTEGRITY OK'.
"""
    def _process_output(self, output: str, state: Dict):
        state['prompt_integrity'] = output

# --- Orchestration Engine ----------------------------------------------------

async def run_orchestration(initial_prompt: str): # Renamed main to run_orchestration
    """The main orchestration loop driven by 'cube'."""
    
    print(f"[*] GENESIS PROMPT: {initial_prompt}\n")
    
    genesis_hash = create_genesis_hash(initial_prompt)
    print(f"[*] GENESIS HASH: {genesis_hash}\n" + "="*80)
    
    shared_state = {
        "status": "STARTING",
        "code_chunks": {},
        "validations": {},
    }
    
    async with aiohttp.ClientSession() as session:
        # Instantiate all agents
        agents = {
            "cube": Cube("CubeOrchestrator", session),
            "wave": Wave("WavePromiser", session),
            "loop": Loop("LoopAdvisor", session),
            "core": Core("CoreExecutor", session),
            "work": Work("WorkValidator", session),
            "code": Code("CodeComposer", session),
            "line": Line("LineResourceManager", session), # Add Line agent
            "coin": Coin("CoinRequestSecurer", session), # Add Coin agent
        }
        
        current_hash = genesis_hash
        max_cycles = 10
        
        for cycle in range(1, max_cycles + 1):
            print(f"\n--- ORCHESTRATION CYCLE {cycle} ---\n")

            # Calculate entropy before Cube makes its decision for this cycle
            current_entropy_score = calculate_entropy(shared_state)
            shared_state['current_entropy_score'] = current_entropy_score
            print(f"[*] Current Entropy Score: {current_entropy_score:.2f}")
            
            # Cube decides the current action
            cube_result = await agents["cube"].reason_and_act(initial_prompt, current_hash, shared_state)
            current_hash = cube_result['reasoning_hash'] # Chain the hash
            action = shared_state.get("current_action", "PLAN")
            print(f"[*] CUBE decision ({cube_result['duration_s']}s): {action} | Hash: {current_hash[:16]}")
            
            if action == "COMPLETE":
                print("\n[+] CUBE determined the orchestration is complete.")
                break
                
            # Fractal Concurrency: Run relevant agents in parallel based on the action
            tasks_to_run = []
            if action == "PLAN":
                tasks_to_run.extend([
                    agents["wave"].reason_and_act(initial_prompt, current_hash, shared_state),
                    agents["loop"].reason_and_act(initial_prompt, current_hash, shared_state),
                    agents["line"].reason_and_act(initial_prompt, current_hash, shared_state), # Run Line agent during PLAN
                    agents["coin"].reason_and_act(initial_prompt, current_hash, shared_state)  # Run Coin agent during PLAN
                ])
            elif action == "EXECUTE":
                tasks_to_run.append(agents["core"].reason_and_act(initial_prompt, current_hash, shared_state))
            elif action == "VALIDATE":
                if shared_state.get("last_chunk_id"):
                    tasks_to_run.append(agents["work"].reason_and_act(initial_prompt, current_hash, shared_state))
                else:
                    print("   - No new chunks to validate, skipping validation.")
            elif action == "REFINE":
                tasks_to_run.append(agents["loop"].reason_and_act(initial_prompt, current_hash, shared_state))
            elif action == "COMPOSE":
                 tasks_to_run.append(agents["code"].reason_and_act(initial_prompt, current_hash, shared_state))
            
            if not tasks_to_run:
                print(f"   - No tasks for action '{action}', moving to next cycle.")
                continue

            # Quantum-like parallel execution
            results = await asyncio.gather(*tasks_to_run)
            
            # Log results and update the hash chain
            for res in results:
                print(f"   - {res['agent']} ({res['role']}) completed in {res['duration_s']}s.")
                print(f"     Output: {res['output'][:100].strip()}...")
                print(f"     Fragment Hash: {res['reasoning_hash'][:16]}")
                current_hash = res['reasoning_hash'] # The last agent's hash becomes the new origin
            
            # After agents have run, recalculate entropy for the next cycle
            # (or use the one already calculated at the beginning if Cube doesn't need intermediate results)
            # For now, let's keep it simple and calculate at the start of each cycle.
            # Save shared state to a temporary file for external access (rehashed indexings)
            with open(AI_TMP_DIR / "_current_orchestration_state.json", "w") as f:
                json.dump(shared_state, f, indent=2)
            
    # --- Final Answer Responsibility ------------------------------------------
    print("\n" + "="*80)
    print("[*] Orchestration Closed. Final Answer Manifested by 'code'.")
    print("="*80)
    
    final_code = shared_state.get("final_script", "# Composition failed. No final script was generated.")
    print(final_code)


if __name__ == "__main__":
    # Get initial prompt from command-line arguments, or use a default
    if len(sys.argv) > 1:
        prompt_arg = sys.argv[1]
    else:
        prompt_arg = "Create a Python script using asyncio to fetch the content of three URLs in parallel and print their status codes and content length."
        print("[*] No prompt provided. Using default prompt for demonstration.")
    
    asyncio.run(run_orchestration(prompt_arg))
