extern void thread_entry(int cid, int nc);

int main(void)
{
  thread_entry(0, 1);
  return 1;
}
