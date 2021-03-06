class Discussion < ActiveRecord::Base

  has_many :discussion_posts

  belongs_to :allocation_tag
  belongs_to :schedule

  def closed?
    self.schedule.end_date < Date.today
  end

  def extra_time?(user_id)
    (self.allocation_tag.is_user_class_responsible?(user_id) and self.closed?) ?
      ((self.schedule.end_date.to_datetime + Discussion_Responsible_Extra_Time) >= Date.today) : false
  end

  def user_can_see?(user_id)
    allocation_tags = AllocationTag.find_related_ids(self.allocation_tag_id).join(',')
    allocations = Allocation.where("allocation_tag_id IN (#{allocation_tags}) AND status = #{Allocation_Activated} AND user_id = #{user_id}")

    (allocations.length > 0) and (self.schedule.start_date <= Date.today)
  end

  def user_can_interact?(user_id)
    return false unless user_can_see?(user_id)
    return (!self.closed? or extra_time?(user_id))
  end

  def posts(opts = {})
    opts = { "type" => 'news', "order" => 'desc', "limit" => 20 }.merge(opts)
    type = (opts["type"] == 'news') ? '>' : '<'

    query = <<SQL
        SELECT t1.id,
               COALESCE(t1.parent_id::text, '') AS parent_id,
               t1.profile_id,
               t1.discussion_id,
               t3.id                          AS user_id,
               t3.nick                        AS user_nick,
               t1.content                     AS content_first,
               ''                             AS content_last,
               to_char(t1.updated_at::timestamp(0), 'YYYYMMDDHH24MISS') AS updated
          FROM discussion_posts AS t1
          JOIN discussions      AS t2 ON t2.id = t1.discussion_id
          JOIN users            AS t3 ON t3.id = t1.user_id
         WHERE t2.id = #{self.id}
           AND t1.updated_at::timestamp(0) #{type} '#{opts["date"].to_time}'::timestamp(0)
         ORDER BY t1.updated_at #{opts["order"]}, t1.id #{opts["order"]}
         LIMIT #{opts["limit"]}
SQL

    ActiveRecord::Base.connection.select_all query
  end

  def count_posts_after_and_before_period(period)
    query = <<SQL
      WITH cte_before AS (
        SELECT count(DISTINCT t1.id) AS before
          FROM discussion_posts AS t1
          JOIN discussions      AS t2 ON t2.id = t1.discussion_id
         WHERE t2.id = #{self.id}
           AND updated_at::timestamp(0) < '#{period.first.to_time}'::timestamp(0)
      ),
      cte_after AS (
        SELECT count(DISTINCT t1.id) AS after
          FROM discussion_posts AS t1
          JOIN discussions      AS t2 ON t2.id = t1.discussion_id
         WHERE t2.id = #{self.id}
           AND updated_at::timestamp(0) > '#{period.last.to_time}'::timestamp(0)
      )
      --
      SELECT (SELECT before FROM cte_before) AS before, (SELECT after FROM cte_after) AS after
SQL

    ActiveRecord::Base.connection.select_all query
  end

  def self.all_by_allocation_tag_id(allocation_tag_id)
    query = <<SQL
      SELECT t1.id,
             CASE WHEN t3.end_date < now() THEN t1.name || ' (fechado)' ELSE t1.name END AS name,
             t1.description,
             CASE WHEN t3.end_date < now() THEN true ELSE false END     AS closed,
             max(to_char(t4.updated_at::timestamp(0), 'YYYYMMDDHH24MISS')) AS last_post_date
        FROM discussions      AS t1
        JOIN allocation_tags  AS t2 ON t2.id = t1.allocation_tag_id
        JOIN schedules        AS t3 ON t3.id = t1.schedule_id
   LEFT JOIN discussion_posts AS t4 ON t4.discussion_id = t1.id
       WHERE t2.id = #{allocation_tag_id}
       GROUP BY t1.id, t3.end_date, t1.name, t1.allocation_tag_id, t1.description, t1.schedule_id
       ORDER BY closed, last_post_date DESC
SQL

    ActiveRecord::Base.connection.select_all query
  end

  def closed?
    Schedule.find(self.schedule_id).end_date.to_time < Time.now.to_time
  end

end
