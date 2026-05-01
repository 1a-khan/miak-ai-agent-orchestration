defmodule MiakTech.DB do
  @conn :miak_db

  def child_spec(_opts) do
    cfg = Application.fetch_env!(:miak_tech, MiakTech.DB)

    %{
      id:    __MODULE__,
      start: {Postgrex, :start_link, [Keyword.put(cfg, :name, @conn)]},
      type:  :worker
    }
  end

  def setup do
    Postgrex.query!(@conn, """
      CREATE TABLE IF NOT EXISTS agents (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        role VARCHAR(50),
        department VARCHAR(50),
        budget_total DECIMAL(10,4),
        budget_used DECIMAL(10,4) DEFAULT 0,
        inserted_at TIMESTAMP DEFAULT NOW()
      )
    """, [])

    Postgrex.query!(@conn, """
      CREATE TABLE IF NOT EXISTS messages (
        id SERIAL PRIMARY KEY,
        agent_name VARCHAR(100),
        direction VARCHAR(20),
        content TEXT,
        tokens_used INTEGER DEFAULT 0,
        cost_usd DECIMAL(10,6) DEFAULT 0,
        inserted_at TIMESTAMP DEFAULT NOW()
      )
    """, [])

    Postgrex.query!(@conn, """
      CREATE TABLE IF NOT EXISTS tasks (
        id SERIAL PRIMARY KEY,
        title TEXT,
        assigned_by VARCHAR(100),
        assigned_to VARCHAR(100),
        status VARCHAR(20) DEFAULT 'pending',
        result TEXT,
        inserted_at TIMESTAMP DEFAULT NOW()
      )
    """, [])

    Postgrex.query!(@conn, """
      CREATE TABLE IF NOT EXISTS themes (
        id SERIAL PRIMARY KEY,
        title VARCHAR(255),
        description TEXT,
        source_email_id VARCHAR(500),
        source_from VARCHAR(255),
        status VARCHAR(20) DEFAULT 'proposed',
        inserted_at TIMESTAMP DEFAULT NOW()
      )
    """, [])

    Postgrex.query!(@conn, """
      CREATE TABLE IF NOT EXISTS files (
        id SERIAL PRIMARY KEY,
        theme_id INTEGER REFERENCES themes(id) ON DELETE SET NULL,
        client_name VARCHAR(255) DEFAULT 'unknown',
        category VARCHAR(50) DEFAULT 'other',
        filename VARCHAR(500),
        original_filename VARCHAR(500),
        s3_key TEXT,
        s3_bucket VARCHAR(255),
        size_bytes INTEGER,
        project_name VARCHAR(255),
        task_name VARCHAR(255),
        uploaded_by VARCHAR(100) DEFAULT 'telegram',
        inserted_at TIMESTAMP DEFAULT NOW()
      )
    """, [])

    Postgrex.query(@conn,
      "ALTER TABLE agents ADD CONSTRAINT agents_name_unique UNIQUE (name)", [])

    :ok
  end

  def seed_agents do
    for {name, role, dept, budget} <- [
      {"CTO",           "cto",           "executive",  2.0},
      {"Programmer",    "programmer",    "it",         4.0},
      {"Administrator", "administrator", "it",         4.0},
      {"Jordan",        "email_manager", "operations", 1.0},
      {"Aria",          "files_manager", "operations", 1.0}
    ] do
      Postgrex.query!(@conn, """
        INSERT INTO agents (name, role, department, budget_total)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (name) DO NOTHING
      """, [name, role, dept, budget])
    end

    :ok
  end

  def log_message(agent, direction, content, tokens, cost) do
    Postgrex.query!(@conn,
      "INSERT INTO messages (agent_name, direction, content, tokens_used, cost_usd) VALUES ($1, $2, $3, $4, $5)",
      [agent, direction, content, tokens, cost])

    log_line = "[#{agent}] [#{direction}] tokens=#{tokens} cost=$#{Float.round(cost * 1.0, 6)} | #{String.slice(content, 0, 200)}"
    MiakTech.Grafana.push_log(agent, direction, log_line)
  end

  def update_budget(agent, cost) do
    Postgrex.query!(@conn,
      "UPDATE agents SET budget_used = budget_used + $1 WHERE name = $2",
      [cost, agent])
  end

  def log_task(title, from, to) do
    %{rows: [[id]]} = Postgrex.query!(@conn,
      "INSERT INTO tasks (title, assigned_by, assigned_to) VALUES ($1, $2, $3) RETURNING id",
      [title, from, to])
    id
  end

  def complete_task(id, result) do
    Postgrex.query!(@conn,
      "UPDATE tasks SET status = 'done', result = $1 WHERE id = $2",
      [result, id])
  end

  def budget_report do
    %{rows: rows} = Postgrex.query!(@conn,
      "SELECT name, budget_total, budget_used FROM agents ORDER BY name", [])
    %{rows: [[total_budget, total_used]]} = Postgrex.query!(@conn,
      "SELECT SUM(budget_total), SUM(budget_used) FROM agents", [])
    rows ++ [["TOTAL", total_budget, total_used]]
  end
end
