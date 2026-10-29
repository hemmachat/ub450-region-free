// Test harness for RegionPatch.parseValue(int,int,int): feeds three char codes
// (as ints, -1 = EOF) and prints the parsed value. Runs on a normal JVM; the
// probe class only needs the Philips classes on the classpath to load.
public class ValueHarness {
    public static void main(String[] a) throws Exception {
        Class c = Class.forName("com.mtk.utils.RegionPatch");
        if ("default".equals(a[0])) {
            java.lang.reflect.Method m = c.getDeclaredMethod("valueOrDefault",
                    new Class[] {int.class});
            m.setAccessible(true);
            Object r = m.invoke(null, new Object[] {Integer.valueOf(a[1])});
            System.out.println(((Integer) r).intValue());
            return;
        }
        java.lang.reflect.Method m = c.getDeclaredMethod("parseValue",
                new Class[] {int.class, int.class, int.class});
        m.setAccessible(true);
        Object r = m.invoke(null, new Object[] {
                Integer.valueOf(a[0]), Integer.valueOf(a[1]), Integer.valueOf(a[2])});
        System.out.println(((Integer) r).intValue());
    }
}
