# Task C: Optimization & Internals

## Question 1: Event Loop & CPU Blocking

**Scenario:** In our main.py , we used asyncio.sleep(3) . In a real scenario,
calculating sentiment_score using a Transformer model (similar to your ML work at
NCBA Bank) is a CPU-bound operation..

**Question:** What happens to the FastAPI server if we run a heavy CPU task directly inside an
async def function? How does this affect the Python Global Interpreter Lock (GIL) and
other incoming requests? Explain how you would re-architect the code to solve this blocking
issue without adding new servers.

**Answer:**

FastAPI runs on an asynchronous event loop via an ASGI server such as Uvicorn, which uses asyncio (or uvloop) to execute async request handlers. The event loop relies on tasks yielding control (await) so it can serve other requests. If a CPU-bound operation (e.g., The Transformer model used for sentiment inference) runs directly inside an async def function, it blocks the event loop until completion. as a result The worker cannot process other incoming requests. The Python Global Interpreter Lock (GIL) further worsens this as it is a mutex lock that allows only one thread to execute Python bytecode at a time per process, so CPU-heavy Python code won’t run truly in parallel within a single process.

The soultion to this without adding new servers is to use parallelism and multiprocessing

- One way you can achieve this is by adding multiple Uvicorn workers when running the app allowing CPU work to run in parallel across cores:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
```
- Another way to achieve this is by offloading the CPU-bound inference to a ProcessPoolExecutor in the main.py code to achieve multiprocessing so the event loop remains responsive (multiprocessing bypasses the GIL).
```python
from concurrent.futures import ProcessPoolExecutor
```
 
## Question 2: Memory Management (Streaming vs. Loading)

**Scenario:** A client uploads a massive transcript file 500MB JSON. If we load this into a Pydantic model, Python might consume 2GB+ of RAM due to overhead, triggering an OOM kill.

**Question:** How would you process this large JSON file in Python without loading the entire object into memory at once? Describe the specific Python libraries or patterns you would use. (Compare this to how Spark handles large datasets with lazy evaluation and partitioning.)

**Answer:** 

The solution to processing this large JSON file in Python is to stream and process the data incrementally, rather than loading the full object. Use FastAPI UploadFile function to receive the large files which provides a file-like object instead of reading the entire request body into memory. Then use a streaming JSON parser such as ijson. ijson parses JSON incrementally and yields items one at a time from a stream, so memory usage stays bounded regardless of file size.

a possible pattern could be: 
- Stream the file
- Iterate over each JSON object (e.g., each transcript chunk)
- Validate/process one record
- Persist it
- Discard it from memory

This method of using ijson is similar to the way spark handles large data files: 
- Lazy evaluation: transformations are not executed until an action is triggered.
- Partitioning: data is split into partitions and processed independently across executors.

Spark therefore never requires the entire dataset to be loaded into driver memory at once.

## Question 3: Database Indexing Strategy

**Scenario:** Our Transcript table has 500 million rows. We need to frequently query by
tenant_id AND created_at (to show the last 7 days of data).

**Question:** Explain the difference between a B Tree Index and a Hash Index. Which would you choose for this specific query pattern and why? What is the "write penalty" of adding too many indexes?

**Answer:** 

A B-Tree index stores keys in sorted, tree data structure and supports:
- Equality queries(=)
- Range queries(>, <, BETWEEN)
- Ordered scans (ORDER BY)
- Composite indexes

Because keys are ordered, B-Trees efficiently support time-based filtering

A Hash index takes the key of the value that you are indexing and hashes it into buckets using a hash function. a hash index:
- Optimized for equality lookups only
- Does not preserve ordering
- Cannot support range queries

The best index to chose to query by tenant_id AND created_at would be a btree index. This is due to the fact that tenant_id as an id has high cardinality which narrows the search space and created_at supports range queries. A Hash index is unsuitable because it cannot efficiently evaluate range conditions on created_at as it does not preserve ordering.

The  "write penalty" of adding too many indexes refers to the fact that indexes improve read performance but slow down writes.

Every INSERT, UPDATE, or DELETE must:
- Modify the base table
- Update all associated indexes

As the number of indexes increases:
- Write latency increases
- Disk and WAL I/O increase
- Ingestion throughput decreases
